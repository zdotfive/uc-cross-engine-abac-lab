"""Control for the DuckDB result: the same reader and the same DuckDB setup on tables
without rules (ctrl_delta_plain, ctrl_delta_cm, ctrl_ice) and with rules (ctrl_ice_rules).
  0) Iceberg REST loadTable: scan-planning-mode and storage credentials (prefixes only)
  A) Iceberg REST ATTACH + SELECT
  B) temporary-table-credentials READ + delta_scan / iceberg_scan
If DuckDB reads the tables without rules and not the one with rules, the rules are what stop it."""
import sys, time, duckdb, requests
sys.path.insert(0, __import__("os").path.dirname(__file__))
from rest import env, HOST, IRC, CATALOG, reader_headers, short
import os
REGION = os.environ.get("DATA_REGION", "eu-west-1")

TABLES = ["ctrl_delta_plain", "ctrl_delta_cm", "ctrl_uniform", "ctrl_ice", "ctrl_ice_rules"]
H = reader_headers()
con = duckdb.connect()
for ext in ("httpfs", "iceberg", "delta"):
    con.sql(f"INSTALL {ext}; LOAD {ext};")
print("catalog", CATALOG, "data region", REGION)
print("duckdb", duckdb.__version__, con.sql("SELECT extension_name, extension_version FROM duckdb_extensions() "
      "WHERE extension_name IN ('httpfs','iceberg','delta') ORDER BY 1").fetchall())


def run(label, q):
    t0 = time.perf_counter()
    try:
        rows = con.sql(q).fetchall()
        print(f"{label:34s} DATA RETURNED ({time.perf_counter()-t0:.3f}s): {rows[:4]}")
    except Exception as e:
        print(f"{label:34s} error ({time.perf_counter()-t0:.3f}s): {type(e).__name__}: {' '.join(str(e).split())[:300]}")


print("\n=== 0) Iceberg REST loadTable")
for t in TABLES:
    for deleg in (None, "vended-credentials"):
        h = dict(H, **({"X-Iceberg-Access-Delegation": deleg} if deleg else {}))
        r = requests.get(f"{IRC}/namespaces/xabac_ctrl/tables/{t}", headers=h)
        if r.status_code != 200:
            print(f"{t:18s} delegation={deleg!s:19s} {short(r, 220)}"); continue
        b = r.json()
        creds = b.get("storage-credentials", []) or []
        cfg_keys = sorted((b.get("config") or {}).keys())
        mode = (b.get("config") or {}).get("scan-planning-mode", "<not set>")
        print(f"{t:18s} delegation={deleg!s:19s} HTTP 200 scan-planning-mode={mode} "
              f"storage-credentials={len(creds)} prefixes={[c.get('prefix', '')[-45:] for c in creds]} "
              f"credential-keys={sorted({k for c in creds for k in (c.get('config') or {})})} config-keys={cfg_keys}")

print("\n=== A) Iceberg REST ATTACH")
con.execute(f"""CREATE SECRET uc_rest (TYPE iceberg, CLIENT_ID '{env["DATABRICKS_CLIENT_ID"]}',
                CLIENT_SECRET '{env["DATABRICKS_CLIENT_SECRET"]}', OAUTH2_SERVER_URI '{HOST}/oidc/v1/token',
                OAUTH2_SCOPE 'all-apis')""")
con.execute(f"""ATTACH '{CATALOG}' AS uc (TYPE iceberg, SECRET uc_rest, DEFAULT_REGION '{REGION}',
                ENDPOINT '{HOST}/api/2.1/unity-catalog/iceberg-rest')""")
for t in TABLES:
    run(f"{t} count by country", f"SELECT country, count(*) FROM uc.xabac_ctrl.{t} GROUP BY 1 ORDER BY 1")
    run(f"{t} email,iban", f"SELECT email, iban FROM uc.xabac_ctrl.{t} LIMIT 2")

print("\n=== B) credential vending")
for t in TABLES:
    info = requests.get(f"{HOST}/api/2.1/unity-catalog/tables/{CATALOG}.xabac_ctrl.{t}", headers=H).json()
    r = requests.post(f"{HOST}/api/2.1/unity-catalog/temporary-table-credentials", headers=H,
                      json={"table_id": info["table_id"], "operation": "READ"})
    print(f"{t:34s} temporary-table-credentials READ -> {short(r, 220) if r.status_code != 200 else 'HTTP 200 (credentials issued)'}")
    if r.status_code != 200:
        continue
    c = r.json()["aws_temp_credentials"]
    loc = info["storage_location"]
    con.execute(f"""CREATE OR REPLACE SECRET s_{t} (TYPE s3, KEY_ID '{c['access_key_id']}',
                    SECRET '{c['secret_access_key']}', SESSION_TOKEN '{c['session_token']}',
                    REGION '{REGION}', SCOPE '{loc}')""")
    if info.get("data_source_format") == "DELTA" and "ice" not in t:
        run(f"{t} delta_scan", f"SELECT country, count(*) FROM delta_scan('{loc}') GROUP BY 1 ORDER BY 1")
    else:
        run(f"{t} iceberg_scan", f"SELECT country, count(*) FROM iceberg_scan('{loc}', allow_moved_paths := true) GROUP BY 1 ORDER BY 1")
