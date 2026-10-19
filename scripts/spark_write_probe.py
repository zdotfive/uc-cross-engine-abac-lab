"""External write attempts from local Spark as the reader, on tables with rules.
Usage: python scripts/spark_write_probe.py <iceberg|delta> <table> [<table> ...]"""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from spark_session import load_env, iceberg_session, delta_session

engine, tables = sys.argv[1], sys.argv[2:]
env = load_env()
spark = iceberg_session(env) if engine == "iceberg" else delta_session(env, auth="token")
spark.sparkContext.setLogLevel("ERROR")
for t in tables:
    q = (f"INSERT INTO labs.xabac_lab.{t} VALUES "
         f"(99999999, 'External Write', 'external@example.com', 'XX00X0', 'DE', CAST(1 AS DECIMAL(10,2)))")
    print(f"\n[{engine}] > {q}")
    t0 = time.perf_counter()
    try:
        spark.sql(q).collect()
        print(f"  WRITE ACCEPTED ({time.perf_counter() - t0:.3f}s)")
    except Exception as e:
        msg = " ".join(str(e).split("\n\tat ")[0].split())
        print(f"  error ({time.perf_counter() - t0:.3f}s): {type(e).__name__}: {msg[:700]}")
        for line in str(e).splitlines():
            if line.startswith("Caused by:"):
                print("   ", " ".join(line.split())[:400])
spark.stop()
