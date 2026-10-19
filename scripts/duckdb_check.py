"""DuckDB (not a supported engine) on the lab tables, as the reader:
  A) Iceberg REST loadTable as seen by any client: scan-planning-mode, storage-credentials
  B) DuckDB ATTACH through the Iceberg REST catalog (iceberg + httpfs), DEFAULT_REGION set
  C) credential vending (temporary-table-credentials READ) + delta_scan
"""
import sys, time, duckdb, requests
sys.path.insert(0, __import__("os").path.dirname(__file__))
from rest import env, HOST, IRC, reader_headers, short

TABLES = [f"customers_{s}_{v}{a}" for s in ("small", "big") for v in ("delta", "ice", "uniform") for a in ("", "_abac")]
H = reader_headers()
print("duckdb", duckdb.__version__)

print("\n=== A) Iceberg REST loadTable")
for t in TABLES:
    for deleg in (None, "vended-credentials"):
        h = dict(H, **({"X-Iceberg-Access-Delegation": deleg} if deleg else {}))
        r = requests.get(f"{IRC}/namespaces/xabac_lab/tables/{t}", headers=h)
        if r.status_code == 200:
            b = r.json()
            print(f"{t:30s} delegation={deleg!s:19s} HTTP 200 config={b.get('config')} "
                  f"storage-credentials={len(b.get('storage-credentials', []))}")
        else:
            print(f"{t:30s} delegation={deleg!s:19s} {short(r, 300)}")

print("\n=== B) DuckDB ATTACH")
con = duckdb.connect()
for ext in ("httpfs", "iceberg", "delta"):
    con.sql(f"INSTALL {ext}; LOAD {ext};")
print("extensions:", con.sql("SELECT extension_name, extension_version FROM duckdb_extensions() "
                             "WHERE extension_name IN ('httpfs','iceberg','delta') ORDER BY 1").fetchall())
con.execute(f"""CREATE SECRET uc_rest (TYPE iceberg, CLIENT_ID '{env["DATABRICKS_CLIENT_ID"]}',
                CLIENT_SECRET '{env["DATABRICKS_CLIENT_SECRET"]}', OAUTH2_SERVER_URI '{HOST}/oidc/v1/token',
                OAUTH2_SCOPE 'all-apis')""")
con.execute(f"""ATTACH 'labs' AS uc (TYPE iceberg, SECRET uc_rest, DEFAULT_REGION 'eu-west-1',
                ENDPOINT '{HOST}/api/2.1/unity-catalog/iceberg-rest')""")
print("ATTACH ok")
for t in TABLES:
    for q in (f"SELECT country, count(*) FROM uc.xabac_lab.{t} GROUP BY 1 ORDER BY 1",
              f"SELECT email, iban FROM uc.xabac_lab.{t} LIMIT 3"):
        t0 = time.perf_counter()
        try:
            rows = con.sql(q).fetchall()
            print(f"{t:30s} DATA RETURNED ({time.perf_counter()-t0:.3f}s): {rows[:5]}  <-- {q[:40]}")
        except Exception as e:
            msg = " ".join(str(e).split())
            print(f"{t:30s} error ({time.perf_counter()-t0:.3f}s): {type(e).__name__}: {msg[:330]}")

print("\n=== C) temporary-table-credentials READ + delta_scan")
for t in TABLES:
    info = requests.get(f"{HOST}/api/2.1/unity-catalog/tables/labs.xabac_lab.{t}", headers=H).json()
    r = requests.post(f"{HOST}/api/2.1/unity-catalog/temporary-table-credentials", headers=H,
                      json={"table_id": info["table_id"], "operation": "READ"})
    print(f"{t:30s} {short(r, 260)}")
    if r.status_code == 200:
        print("   CREDENTIALS ISSUED: not used further, report to the owner")
