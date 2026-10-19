"""Spark sessions for the two documented cross-engine ABAC paths, authenticated as the
reader service principal. Credentials come from .env (or the environment) and are never printed.

  iceberg: Iceberg REST catalog of Unity Catalog (Iceberg-Spark 1.11.0)
  delta:   Delta-Spark 4.1.0 + Unity Catalog Spark connector 0.4.0, server-side planning
"""
import os
from dotenv import dotenv_values
from pyspark.sql import SparkSession

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CAT = "labs"
ICEBERG_VERSION = "1.11.0"
DELTA_PACKAGES = ("io.delta:delta-spark_4.0_2.13:4.1.0,io.delta:delta-iceberg_2.13:4.1.0,"
                  "io.unitycatalog:unitycatalog-spark_2.13:0.4.0,org.apache.hadoop:hadoop-aws:3.4.1")


def load_env():
    env = dict(dotenv_values(os.path.join(ROOT, ".env")))
    for k in ("DATABRICKS_HOST", "DATABRICKS_WORKSPACE_ID", "DATABRICKS_CLIENT_ID", "DATABRICKS_CLIENT_SECRET"):
        env.setdefault(k, os.environ.get(k))
        if not env.get(k):
            env[k] = os.environ.get(k)
    env["DATABRICKS_HOST"] = env["DATABRICKS_HOST"].rstrip("/")
    return env


def reader_token(env):
    """OAuth M2M access token for the reader, kept in memory."""
    import requests
    r = requests.post(f"{env['DATABRICKS_HOST']}/oidc/v1/token",
                      auth=(env["DATABRICKS_CLIENT_ID"], env["DATABRICKS_CLIENT_SECRET"]),
                      data={"grant_type": "client_credentials", "scope": "all-apis"})
    r.raise_for_status()
    return r.json()["access_token"]


def iceberg_session(env, scope="all-apis", extra=None):
    host = env["DATABRICKS_HOST"]
    b = (SparkSession.builder.appName("xabac-iceberg")
         .config("spark.jars.packages",
                 f"org.apache.iceberg:iceberg-spark-runtime-4.0_2.13:{ICEBERG_VERSION},"
                 f"org.apache.iceberg:iceberg-aws-bundle:{ICEBERG_VERSION}")
         .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
         .config(f"spark.sql.catalog.{CAT}", "org.apache.iceberg.spark.SparkCatalog")
         .config(f"spark.sql.catalog.{CAT}.type", "rest")
         .config(f"spark.sql.catalog.{CAT}.uri", f"{host}/api/2.1/unity-catalog/iceberg-rest/")
         .config(f"spark.sql.catalog.{CAT}.credential", f"{env['DATABRICKS_CLIENT_ID']}:{env['DATABRICKS_CLIENT_SECRET']}")
         .config(f"spark.sql.catalog.{CAT}.oauth2-server-uri", f"{host}/oidc/v1/token")
         .config(f"spark.sql.catalog.{CAT}.warehouse", CAT)
         .config(f"spark.sql.catalog.{CAT}.cache-enabled", "false")
         .config("spark.sql.defaultCatalog", CAT))
    # Not in the docs' example: without it Iceberg asks for scope "catalog" and gets 403.
    if scope:
        b = b.config(f"spark.sql.catalog.{CAT}.scope", scope)
    for k, v in (extra or {}).items():
        b = b.config(k, v)
    return b.getOrCreate()


def delta_session(env, auth="token", uri_with_workspace_id=False, extra=None):
    host = env["DATABRICKS_HOST"]
    uri = f"{host}/?o={env['DATABRICKS_WORKSPACE_ID']}" if uri_with_workspace_id else host
    b = (SparkSession.builder.appName("xabac-delta")
         .config("spark.jars.packages", DELTA_PACKAGES)
         .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
         .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
         .config(f"spark.sql.catalog.{CAT}", "io.unitycatalog.spark.UCSingleCatalog")
         .config(f"spark.sql.catalog.{CAT}.uri", uri)
         .config(f"spark.sql.catalog.{CAT}.ServerSidePlanning.enabled", "true")
         .config("spark.sql.defaultCatalog", CAT)
         .config("spark.hadoop.fs.s3.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem"))
    if auth == "oauth":  # as in the docs
        b = (b.config(f"spark.sql.catalog.{CAT}.auth.type", "oauth")
              .config(f"spark.sql.catalog.{CAT}.auth.oauth.uri", f"{host}/oidc/v1/token")
              .config(f"spark.sql.catalog.{CAT}.auth.oauth.clientId", env["DATABRICKS_CLIENT_ID"])
              .config(f"spark.sql.catalog.{CAT}.auth.oauth.clientSecret", env["DATABRICKS_CLIENT_SECRET"]))
    else:  # static access token of the reader
        b = b.config(f"spark.sql.catalog.{CAT}.token", reader_token(env))
    for k, v in (extra or {}).items():
        b = b.config(k, v)
    return b.getOrCreate()
