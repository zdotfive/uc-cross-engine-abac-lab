"""EMR Serverless job: the bench.py queries through the Unity Catalog Iceberg REST catalog,
as the reader service principal. The reader's OAuth credentials are read at runtime from
AWS Secrets Manager and never printed.

Arguments: <databricks-host> <secret-id> <region> <s3-output-uri> <table,table,...> [reps]

One Spark session is used for all tables (one job, one application), so the first query on
each table is "first on that table", not "first in a fresh JVM".
"""
import json, sys, time
import boto3
from pyspark.sql import SparkSession

host, secret_id, region, out_uri, tables = sys.argv[1:6]
reps = int(sys.argv[6]) if len(sys.argv) > 6 else 3
host = host.rstrip("/")
cred = json.loads(boto3.client("secretsmanager", region_name=region)
                  .get_secret_value(SecretId=secret_id)["SecretString"])

QUERIES = {
    "q1_group_by_country": "SELECT country, count(*) AS n FROM {t} GROUP BY country ORDER BY country",
    "q2_email_iban_limit5": "SELECT email, iban FROM {t} LIMIT 5",
    "q3_count": "SELECT count(*) AS n FROM {t}",
    "q4_sum_spend": "SELECT CAST(sum(annual_spend) AS STRING) AS total FROM {t}",
}
CAT = "labs"
t0 = time.perf_counter()
spark = (SparkSession.builder.appName("xabac-emr-iceberg")
         .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
         .config(f"spark.sql.catalog.{CAT}", "org.apache.iceberg.spark.SparkCatalog")
         .config(f"spark.sql.catalog.{CAT}.type", "rest")
         .config(f"spark.sql.catalog.{CAT}.uri", f"{host}/api/2.1/unity-catalog/iceberg-rest/")
         .config(f"spark.sql.catalog.{CAT}.credential", f"{cred['client_id']}:{cred['client_secret']}")
         .config(f"spark.sql.catalog.{CAT}.oauth2-server-uri", f"{host}/oidc/v1/token")
         .config(f"spark.sql.catalog.{CAT}.scope", "all-apis")
         .config(f"spark.sql.catalog.{CAT}.warehouse", CAT)
         .config(f"spark.sql.catalog.{CAT}.cache-enabled", "false")
         .config("spark.sql.defaultCatalog", CAT)
         .getOrCreate())
records = []


def emit(rec):
    rec = {"engine": "emr-serverless-iceberg", "principal": "reader", "spark": spark.version, **rec}
    records.append(rec)
    print(json.dumps(rec), flush=True)


emit({"event": "session_start", "seconds": round(time.perf_counter() - t0, 6)})
violation = False
for t in tables.split(","):
    full = f"labs.xabac_lab.{t}"
    for qid, q in QUERIES.items():
        for rep in range(1, reps + 1):
            s = time.perf_counter()
            try:
                rows = [tuple(r) for r in spark.sql(q.format(t=full)).collect()]
            except Exception as e:
                causes = [l.strip() for l in str(e).splitlines() if l.startswith("Caused by:")]
                emit({"table": t, "event": "query", "query": qid, "rep": rep,
                      "seconds": round(time.perf_counter() - s, 6),
                      "error": f"{type(e).__name__}: {str(e).splitlines()[0][:300]}",
                      "causes": [c[:300] for c in causes[:4]]})
                violation = None  # stop the whole run at the first error
                break
            emit({"table": t, "event": "query", "query": qid, "rep": rep, "seconds": round(time.perf_counter() - s, 6),
                  "rows": len(rows), "result": [list(map(str, r)) for r in rows[:5]]})
            if (qid == "q1_group_by_country" and any(r[0] != "IT" for r in rows)) or \
               (qid == "q2_email_iban_limit5" and any(v != "****" for r in rows for v in r)):
                emit({"table": t, "event": "VIOLATION", "query": qid})
                violation = True
                break
        if violation is not False:
            break
    if violation is not False:
        break

bucket, key = out_uri.replace("s3://", "").split("/", 1)
boto3.client("s3", region_name=region).put_object(
    Bucket=bucket, Key=key, Body="\n".join(json.dumps(r) for r in records).encode())
spark.stop()
sys.exit(3 if violation else (1 if violation is None else 0))
