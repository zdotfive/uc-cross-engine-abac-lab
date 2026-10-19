"""Read-only bypass attempts as the reader. Each one is expected to be denied.
  1. temporary-table-credentials READ and READ_WRITE
  2. temporary-path-credentials (PATH_READ) on the table storage location
  3. direct S3 access to files named in the Iceberg metadata: unsigned GET, and (if AWS_PROFILE
     is set) a signed HEAD with that AWS identity. HEAD only: no file content is read. Note that
     an identity with IAM access to the workspace storage bucket is outside Unity Catalog.
  4. Iceberg REST loadTable with X-Iceberg-Access-Delegation: vended-credentials
  5. Iceberg REST server-side scan plan: what the response hands to the client
(External writes are tested separately in spark_write_probe.py.)
"""
import json, os, subprocess, sys
import requests
sys.path.insert(0, os.path.dirname(__file__))
from rest import HOST, IRC, reader_headers, short, redact

SECTIONS = set(os.environ.get("SECTIONS", "1,2,3,4,5").split(","))
TABLES = [f"customers_small_{v}{a}" for v in ("delta", "ice", "uniform") for a in ("", "_abac")]
H = reader_headers()
info = {t: requests.get(f"{HOST}/api/2.1/unity-catalog/tables/labs.xabac_lab.{t}", headers=H).json() for t in TABLES}

if "1" in SECTIONS:
    print("=== 1. temporary-table-credentials")
    for t in TABLES:
        for op in ("READ", "READ_WRITE"):
            r = requests.post(f"{HOST}/api/2.1/unity-catalog/temporary-table-credentials", headers=H,
                              json={"table_id": info[t]["table_id"], "operation": op})
            print(f"{t:28s} {op:10s} {short(r, 330)}")

if "2" in SECTIONS:
    print("\n=== 2. temporary-path-credentials on the storage location")
    for t in TABLES:
        loc = info[t].get("storage_location")
        r = requests.post(f"{HOST}/api/2.0/unity-catalog/temporary-path-credentials", headers=H,
                          json={"url": loc, "operation": "PATH_READ"})
        print(f"{t:28s} {short(r, 330)}")

if "3" in SECTIONS:
    print("\n=== 3. direct S3 reads of files named in the Iceberg metadata")
    for t in [x for x in TABLES if "delta" not in x]:
        b = requests.get(f"{IRC}/namespaces/xabac_lab/tables/{t}", headers=H).json()
        meta = b["metadata-location"]
        snaps = b["metadata"].get("snapshots", [])
        targets = [meta] + [s["manifest-list"] for s in snaps[:1]]
        for uri in targets:
            bucket, key = uri.replace("s3://", "").split("/", 1)
            u = requests.get(f"https://{bucket}.s3.eu-west-1.amazonaws.com/{key}")
            code = u.text.split("<Code>")[1].split("</Code>")[0] if "<Code>" in u.text else u.text[:80]
            print(f"{t:28s} unsigned GET {key.rsplit('/', 1)[-1][:50]:50s} HTTP {u.status_code} {code}")
            if os.environ.get("AWS_PROFILE"):
                p = subprocess.run(["aws", "s3api", "head-object", "--bucket", bucket, "--key", key, "--region", "eu-west-1",
                                    "--query", "{ContentLength:ContentLength}", "--output", "json"], capture_output=True, text=True)
                res = " ".join((p.stdout if p.returncode == 0 else p.stderr).split())[:200]
                print(f"{t:28s} signed HEAD ({os.environ['AWS_PROFILE']}) exit={p.returncode} {res}")

if "4" in SECTIONS:
    print("\n=== 4. loadTable with vended-credentials delegation")
    for t in TABLES:
        r = requests.get(f"{IRC}/namespaces/xabac_lab/tables/{t}",
                         headers=dict(H, **{"X-Iceberg-Access-Delegation": "vended-credentials"}))
        if r.status_code == 200:
            b = r.json()
            print(f"{t:28s} HTTP 200 config={b.get('config')} storage-credentials={b.get('storage-credentials')}")
        else:
            print(f"{t:28s} {short(r, 250)}")

if "5" in SECTIONS:
    print("\n=== 5. server-side scan plan (what the client receives)")
    for t in [x for x in TABLES if "delta" not in x] + ["customers_small_delta"]:
        r = requests.post(f"{IRC}/namespaces/xabac_lab/tables/{t}/plan", headers=H, json={"case-sensitive": False})
        if r.status_code != 200:
            print(f"{t:28s} {short(r, 300)}"); continue
        b = r.json()
        tasks = b.get("file-scan-tasks", [])
        paths = sorted({x.get("data-file", {}).get("file-path", "")[:90] for x in tasks})
        print(f"{t:28s} HTTP 200 keys={sorted(b.keys())} status={b.get('status')} tasks={len(tasks)} "
              f"plan-tasks={len(b.get('plan-tasks', []))} storage-credentials="
              f"{[sc.get('prefix') for sc in b.get('storage-credentials', [])]}")
        for p_ in paths[:3]:
            print(f"{'':28s}   data file: {p_}")
        if tasks:
            print(f"{'':28s}   first task (redacted): {json.dumps(redact(tasks[0]))[:400]}")
