# Unity Catalog row filters, column masks and ABAC, read from outside Databricks

Unity Catalog can enforce row filters, column masks and ABAC policies when a table is read by an
engine that is not Databricks (cross-engine ABAC). This lab checks that on a Databricks Free
Edition workspace with one non-admin service principal and four readers:

- the Databricks SQL warehouse (baseline);
- local Spark 4.0 through the Unity Catalog Iceberg REST catalog;
- local Spark 4.0 with Delta and the Unity Catalog Spark connector (server-side planning);
- EMR Serverless (Spark 4.1) through the Iceberg REST catalog;

plus DuckDB, which is not a supported engine, and a set of attempts to get around the rules.

Results: [results/SUMMARY.md](results/SUMMARY.md). Full log of the run: [results/lab.md](results/lab.md).

## What it shows

- Every supported external path returned only the allowed rows (IT) with `email` and `iban`
  masked, for classic rules and for ABAC policies, on 1,000-row and 10,000,000-row tables.
- The external engine never gets the table files. The catalog answers `scan-planning-mode: server`
  with no storage credentials; the server-side plan points to a new Parquet file holding the
  filtered, masked rows, with credentials for that file only.
- DuckDB got no data from tables with rules, and every credential or path shortcut was refused.
  A control test shows why: on the same tables without rules, the catalog hands out storage
  credentials and DuckDB reads them; with rules, it switches to server-side planning only.
- External access needs a catalog on storage you own: on Databricks default storage
  `EXTERNAL USE SCHEMA` cannot be granted.
- Rules in Unity Catalog do not protect the bucket itself: an IAM identity with access to the
  workspace storage bucket can read the files directly.
- The examples in the docs needed a few changes to work (OAuth scope, table format, auth of the Delta
  connector, EMR jar path and networking). They are listed at the end of the summary.

## Layout

```
sql/        setup, classic rules, ABAC policies, checks, billing, cleanup
scripts/    run_sql.py, bench.py, spark_session.py, duckdb_check.py, bypass_probe.py, ...
emr/        EMR Serverless job and the AWS CLI commands to create, run and delete it
results/    logs, raw measurements (JSONL), lab.md, SUMMARY.md
```

## Requirements

- A Databricks workspace with external data access enabled on the metastore, a SQL warehouse,
  and a Databricks CLI profile for an admin (`PROFILE`, default `FREE`).
- Python 3.11+ and Java 17+ (for local Spark).
- For EMR: an AWS account and an AWS CLI profile allowed to create S3, IAM, Secrets Manager,
  VPC and EMR Serverless resources.

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

## Run

```bash
# 1. reader service principal and .env (see .env.example)
PROFILE=FREE WAREHOUSE_ID=<warehouse-id> bash scripts/create_reader_sp.sh

# 2. tables, rules, grants (admin)
.venv/bin/python scripts/run_sql.py sql/01_setup.sql
.venv/bin/python scripts/run_sql.py sql/02_rules_classic.sql
.venv/bin/python scripts/run_sql.py sql/03_rules_abac.sql
.venv/bin/python scripts/run_sql.py sql/04_check.sql               # admin
.venv/bin/python scripts/run_sql.py sql/04_check.sql --as-reader   # reader

# 3. benchmark: warehouse + local Spark (Iceberg REST and Delta)
JAVA_HOME=<jdk-17+> bash scripts/run_bench_all.sh

# 4. DuckDB and bypass attempts (reader, read-only)
.venv/bin/python scripts/duckdb_check.py
.venv/bin/python scripts/bypass_probe.py

# 5. EMR Serverless
AWS_PROFILE=<profile> bash emr/commands.sh create
AWS_PROFILE=<profile> bash emr/commands.sh network-create
AWS_PROFILE=<profile> bash emr/commands.sh run
AWS_PROFILE=<profile> bash emr/commands.sh wait
AWS_PROFILE=<profile> bash emr/commands.sh fetch
AWS_PROFILE=<profile> bash emr/commands.sh delete
AWS_PROFILE=<profile> bash emr/commands.sh network-delete

# 6. summary tables, cost (next day), cleanup
.venv/bin/python scripts/summarize.py > results/bench_tables.md
.venv/bin/python scripts/run_sql.py sql/08_billing.sql
.venv/bin/python scripts/run_sql.py sql/99_cleanup.sql
databricks --profile FREE service-principals delete <READER_SP_ID from .env>
```

Cross-engine ABAC runs on Databricks serverless compute and is billed
(`billing_origin_product = 'EXTERNAL_COMPATIBILITY'`). The EMR run creates a NAT gateway, which is
billed per hour: run `delete` and `network-delete` as soon as the job is done.

## References

- Databricks: [Cross-engine ABAC](https://docs.databricks.com/aws/en/external-access/cross-engine-abac),
  [Row filters and column masks](https://docs.databricks.com/aws/en/data-governance/unity-catalog/filters-and-masks),
  [ABAC policies](https://docs.databricks.com/aws/en/data-governance/unity-catalog/abac/policies),
  [Governed tags](https://docs.databricks.com/aws/en/admin/governed-tags/manage-governed-tags)
- AWS: [emr-spark-8.1.0](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-spark810-release.html),
  [VPC access for EMR Serverless](https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/vpc-access.html)
