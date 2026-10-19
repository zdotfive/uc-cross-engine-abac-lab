"""Benchmark the same four queries on one table per fresh session.

Usage:
  python scripts/bench.py --engine iceberg|delta|warehouse --principal reader|admin \
      --tables t1,t2 [--reps 3] [--out results/bench/<name>.jsonl]

Engines:
  iceberg    local Spark, Unity Catalog Iceberg REST (reader only)
  delta      local Spark, Delta + UC connector with server-side planning, static token (reader only)
  warehouse  Databricks SQL warehouse, result cache disabled (admin via CLI profile, or reader)

Every table runs in its own process, so each table starts from a fresh session. Each query
runs --reps times; rep 1 is the first run, the others are warm runs. Times are wall clock
around the call that returns the rows to the client.

If the reader sees a country other than IT or a clear-text email/iban, the run stops with
exit code 3 and prints VIOLATION.
"""
import argparse, json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

QUERIES = {
    "q1_group_by_country": "SELECT country, count(*) AS n FROM {t} GROUP BY country ORDER BY country",
    "q2_email_iban_limit5": "SELECT email, iban FROM {t} LIMIT 5",
    "q3_count": "SELECT count(*) AS n FROM {t}",
    "q4_sum_spend": "SELECT CAST(sum(annual_spend) AS STRING) AS total FROM {t}",
}


def check(principal, qid, rows):
    """Return a violation message, or None."""
    if principal != "reader":
        return None
    if qid == "q1_group_by_country" and any(r[0] != "IT" for r in rows):
        return f"reader saw countries {[r[0] for r in rows]}"
    if qid == "q2_email_iban_limit5" and any(v != "****" for r in rows for v in r):
        return "reader saw a clear-text email or iban"
    return None


def spark_runner(engine):
    from spark_session import load_env, iceberg_session, delta_session
    env = load_env()
    t0 = time.perf_counter()
    spark = iceberg_session(env) if engine == "iceberg" else delta_session(env, auth="token")
    spark.sparkContext.setLogLevel("ERROR")
    startup = time.perf_counter() - t0

    def run(sql):
        return [tuple(r) for r in spark.sql(sql).collect()]
    return run, startup, spark.stop, {"spark": spark.version}


def warehouse_runner(principal):
    from dotenv import dotenv_values
    from databricks import sql
    from databricks.sdk.core import Config
    env = dotenv_values(os.path.join(HERE, "..", ".env"))
    if principal == "admin":
        cfg = Config(profile=os.environ.get("PROFILE", "FREE"))
    else:
        cfg = Config(host=env["DATABRICKS_HOST"], client_id=env["DATABRICKS_CLIENT_ID"],
                     client_secret=env["DATABRICKS_CLIENT_SECRET"], auth_type="oauth-m2m")
    t0 = time.perf_counter()
    conn = sql.connect(server_hostname=cfg.host.replace("https://", "").rstrip("/"),
                       http_path=f"/sql/1.0/warehouses/{env['DATABRICKS_WAREHOUSE_ID']}",
                       credentials_provider=lambda: cfg.authenticate,
                       session_configuration={"use_cached_result": "false"})
    cur = conn.cursor()
    startup = time.perf_counter() - t0

    def run(q):
        cur.execute(q)
        return [tuple(r) for r in cur.fetchall()]

    def stop():
        cur.close(); conn.close()
    return run, startup, stop, {}


def one_table(a):
    run, startup, stop, meta = (warehouse_runner(a.principal) if a.engine == "warehouse"
                                else spark_runner(a.engine))
    base = {"engine": a.engine, "principal": a.principal, "table": a.tables, **meta}
    out = open(a.out, "a")

    def emit(rec):
        rec = {**base, **rec}
        out.write(json.dumps(rec) + "\n"); out.flush()
        print(json.dumps(rec))
    emit({"event": "session_start", "seconds": round(startup, 6)})
    full = f"labs.xabac_lab.{a.tables}"
    for qid, q in QUERIES.items():
        for rep in range(1, a.reps + 1):
            t0 = time.perf_counter()
            try:
                rows = run(q.format(t=full))
            except Exception as e:
                emit({"event": "query", "query": qid, "rep": rep, "seconds": round(time.perf_counter() - t0, 6),
                      "error": f"{type(e).__name__}: {str(e)[:600]}"})
                break
            dt = time.perf_counter() - t0
            v = check(a.principal, qid, rows)
            emit({"event": "query", "query": qid, "rep": rep, "seconds": round(dt, 6),
                  "rows": len(rows), "result": [list(map(str, r)) for r in rows[:5]]})
            if v:
                emit({"event": "VIOLATION", "query": qid, "detail": v})
                stop(); sys.exit(3)
    stop()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--engine", required=True, choices=["iceberg", "delta", "warehouse"])
    p.add_argument("--principal", default="reader", choices=["reader", "admin"])
    p.add_argument("--tables", required=True)
    p.add_argument("--reps", type=int, default=3)
    p.add_argument("--out")
    p.add_argument("--one", action="store_true", help=argparse.SUPPRESS)
    a = p.parse_args()
    if a.engine != "warehouse" and a.principal != "reader":
        p.error("local Spark engines run as the reader only")
    a.out = a.out or os.path.join(HERE, "..", "results", "bench", f"{a.engine}_{a.principal}.jsonl")
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    if a.one:
        return one_table(a)
    for t in a.tables.split(","):
        r = subprocess.run([sys.executable, __file__, "--one", "--engine", a.engine, "--principal", a.principal,
                            "--tables", t, "--reps", str(a.reps), "--out", a.out])
        if r.returncode == 3:
            print("VIOLATION: stopping, see", a.out); sys.exit(3)


if __name__ == "__main__":
    main()
