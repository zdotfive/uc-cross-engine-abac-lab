"""One query on the Delta path for a given auth mode and URI form.
Usage: python scripts/delta_auth_probe.py <oauth|token> <host|host+wsid> <table>"""
import sys, time
sys.path.insert(0, __import__("os").path.dirname(__file__))
from spark_session import load_env, delta_session
auth, uri, table = sys.argv[1:4]
spark = delta_session(load_env(), auth=auth, uri_with_workspace_id=(uri == "host+wsid"))
spark.sparkContext.setLogLevel("ERROR")
q = f"SELECT country, count(*) AS n FROM labs.xabac_lab.{table} GROUP BY country ORDER BY country"
print(f"auth={auth} uri={uri}\n> {q}")
t0 = time.perf_counter()
try:
    rows = [r.asDict() for r in spark.sql(q).collect()]
    print(f"  ok ({time.perf_counter() - t0:.3f}s)", rows)
except Exception as e:
    print(f"  error ({time.perf_counter() - t0:.3f}s): {type(e).__name__}: {str(e)[:700]}")
spark.stop()
