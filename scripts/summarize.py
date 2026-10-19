"""Build the benchmark tables for results/SUMMARY.md from results/bench/*.jsonl and
results/emr/emr_bench.jsonl. Rounding happens only here."""
import collections, glob, json, os, statistics as st, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
files = sorted(glob.glob(os.path.join(ROOT, "results", "bench", "*.jsonl")))
emr = os.path.join(ROOT, "results", "emr", "emr_bench.jsonl")
if os.path.exists(emr):
    files.append(emr)

LABEL = {("warehouse", "admin"): "SQL warehouse, admin", ("warehouse", "reader"): "SQL warehouse, reader",
         ("iceberg", "reader"): "Local Spark 4.0.4, Iceberg REST, reader",
         ("delta", "reader"): "Local Spark 4.0.4, Delta + UC connector (static token), reader",
         ("emr-serverless-iceberg", "reader"): "EMR Serverless, Iceberg REST, reader"}

for f in files:
    recs = [json.loads(l) for l in open(f) if l.strip()]
    q = [r for r in recs if r.get("event") == "query" and "error" not in r]
    errs = [r for r in recs if r.get("event") == "query" and "error" in r]
    viol = [r for r in recs if r.get("event") == "VIOLATION"]
    starts = {r.get("table"): r["seconds"] for r in recs if r.get("event") == "session_start"}
    eng, pr = recs[0]["engine"], recs[0]["principal"]
    print(f"\n### {LABEL.get((eng, pr), eng + ', ' + pr)}\n")
    if eng == "emr-serverless-iceberg" and None in starts:
        print(f"Spark session start (once for all tables): {starts[None]:.1f} s\n")
    print("| Table | Rows (count) | Countries | email/iban | Session start (s) | First query (s) | Warm median (s) | Warm min-max (s) |")
    print("|---|---|---|---|---|---|---|---|")
    by = collections.defaultdict(list)
    for r in q:
        by[r["table"]].append(r)
    for t, rs in by.items():
        cnt = next(r["result"][0][0] for r in rs if r["query"] == "q3_count")
        countries = ",".join(x[0] for x in next(r["result"] for r in rs if r["query"] == "q1_group_by_country"))
        q2 = next(r["result"] for r in rs if r["query"] == "q2_email_iban_limit5")
        masked = "masked (****)" if all(v == "****" for row in q2 for v in row) else "clear text"
        first = next(r["seconds"] for r in rs if r["query"] == "q1_group_by_country" and r["rep"] == 1)
        warm = [r["seconds"] for r in rs if r["rep"] > 1]
        s = f"{starts[t]:.1f}" if t in starts else "-"
        print(f"| `{t}` | {int(cnt):,} | {countries} | {masked} | {s} | {first:.2f} | {st.median(warm):.2f} | "
              f"{min(warm):.2f}-{max(warm):.2f} |")
    print(f"\nQueries: {len(q)} ok, {len(errs)} errors, {len(viol)} violations. "
          "First query = q1 (GROUP BY country), first run on that table. Warm = runs 2-3 of q1-q4.")
