"""Size of the server-side scan plan the reader receives: tasks, record counts, bytes."""
import sys, time, requests
sys.path.insert(0, __import__("os").path.dirname(__file__))
from rest import IRC, reader_headers, short
H = reader_headers()
for t in sys.argv[1:]:
    t0 = time.perf_counter()
    r = requests.post(f"{IRC}/namespaces/xabac_lab/tables/{t}/plan", headers=H, json={"case-sensitive": False})
    dt = time.perf_counter() - t0
    if r.status_code != 200:
        print(f"{t:30s} {short(r, 300)}"); continue
    b = r.json(); tasks = b.get("file-scan-tasks", [])
    recs = sum(x["data-file"].get("record-count", 0) for x in tasks)
    size = sum(x["data-file"].get("file-size-in-bytes", 0) for x in tasks)
    print(f"{t:30s} plan {dt:.3f}s status={b.get('status')} tasks={len(tasks)} plan-tasks={len(b.get('plan-tasks', []))} "
          f"records={recs} bytes={size} credential-prefixes={len(b.get('storage-credentials', []))}")
