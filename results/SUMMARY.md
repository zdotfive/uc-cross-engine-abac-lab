# Summary

Run on 2026-10-19 on a Databricks Free Edition workspace (AWS eu-west-1). One reader service
principal (OAuth M2M, not an admin) read the same customer data through four engines.
Rules on every table: rows only for `country = 'IT'`, `email` and `iban` masked as `****`.
Details and exact commands are in [lab.md](lab.md); per-table numbers in
[bench_tables.md](bench_tables.md), raw measurements in `bench/*.jsonl` and `emr/emr_bench.jsonl`.

Data: `small` = 1,000 rows, `big` = 10,000,000 rows, a quarter per country.
Each in three layouts (Delta with catalog commits, managed Iceberg, Delta with catalog commits +
UniForm Iceberg), with classic rules (row filter + column masks) or ABAC (governed tags + policies).

## Did the reader get only what it should?

| Engine | Tables read | Rows seen by the reader | email / iban | Errors | Violations |
|---|---|---|---|---|---|
| SQL warehouse (baseline) | 12 of 12 | IT only: 250 (small), 2,500,000 (big) | `****` | 0 | 0 |
| Local Spark 4.0.4, Iceberg REST | 8 of 8 Iceberg-readable | IT only: 250 / 2,500,000 | `****` | 0 | 0 |
| Local Spark 4.0.4, Delta + UC connector | 8 of 8 Delta | IT only: 250 / 2,500,000 | `****` | 0 | 0 |
| EMR Serverless, Spark 4.1.1, Iceberg REST | 8 of 8 Iceberg-readable | IT only: 250 / 2,500,000 | `****` | 0 | 0 |
| DuckDB 1.5.6 | 0 of 12 | no data | no data | all reads fail | 0 |

Classic rules and ABAC policies gave identical results on every engine.

## Times (seconds, wall clock to rows in the client)

"First" = first query (`GROUP BY country`) on a table; "warm" = median of runs 2-3 of the four
queries. Ranges are across the tables of that engine.

| Engine | First query | Warm median | Notes |
|---|---|---|---|
| SQL warehouse, admin | 0.32-0.53 | 0.30-0.48 | result cache disabled |
| SQL warehouse, reader | 0.43-0.57 | 0.40-0.47 | |
| Local Spark, Iceberg REST | 10.0-12.6 | 1.6-1.8 | new Spark session per table |
| Local Spark, Delta + UC connector | 6.7-12.9 | 3.1-3.4 | new Spark session per table; static token |
| EMR Serverless, Iceberg REST | 29.9 (first of the job), then 1.5-2.1 | 1.0-1.4 | one session for all tables |

Small and big tables take about the same time from outside: the server-side plan for a big
table hands the client one Parquet file with the 2,500,000 filtered, masked rows (22,833,503 bytes);
for a small table, one file with 250 rows (5,576 bytes).

## Bypass attempts (reader, all denied)

| Attempt | Response |
|---|---|
| `temporary-table-credentials` READ, classic rules | 400 `ROW_COLUMN_ACCESS_POLICIES_NOT_SUPPORTED_ON_ASSIGNED_CLUSTERS` |
| `temporary-table-credentials` READ, ABAC | 403 `ABAC policies can only be called with permission enforcing scope` |
| `temporary-table-credentials` READ_WRITE | 400 `EXTERNAL_WRITE_NOT_ALLOWED_FOR_TABLE` (Delta) / 403 `User does not have MODIFY` (Iceberg) |
| `temporary-path-credentials` on the table location | 403 `User does not have EXTERNAL USE LOCATION` |
| Iceberg REST `loadTable` with `X-Iceberg-Access-Delegation: vended-credentials` | 200, `scan-planning-mode: server`, `storage-credentials: []` |
| Unsigned S3 GET of metadata files named by the catalog | 403 `AccessDenied` |
| DuckDB `ATTACH` via Iceberg REST, then `SELECT` | S3 403 (no credentials); Delta tables: 400 "not an Iceberg compatible table" |
| External INSERT from Spark, with and without `MODIFY` | fails; no rows written (admin count unchanged: 1,000, 0 external rows) |

Out of Unity Catalog's reach: on this workspace the storage bucket lives in the same AWS account
as the lab, and an IAM identity of that account can read the table files directly (a signed
`HeadObject` succeeded). Row filters and masks protect the Unity Catalog access paths, not the bucket.

## Cost

| Item | Usage | Price |
|---|---|---|
| Cross-engine ABAC (`EXTERNAL_COMPATIBILITY`, SKU `PREMIUM_JOBS_SERVERLESS_COMPUTE_EUROPE_IRELAND`), lab reader, 2026-10-19 | 1.62 DBU | list 0.39 USD/DBU, about 0.63 USD |
| Same, all of 2026-10-19 (lab + an earlier check) | 2.00 DBU | about 0.78 USD |
| EMR Serverless, successful run (173 s) | 0.273 vCPU-h, 0.683 GB-h | |
| EMR Serverless, two failed runs | 0.033 vCPU-h + 0.083 GB-h; 4.504 vCPU-h + 11.26 GB-h | |

Billing rows for the day were read the same evening; the re-check the next day is in `lab.md`.
On Free Edition the DBU price is the list price shown in `system.billing.list_prices`, not a charge.

## Gaps between the docs and what happened

1. Iceberg REST config from the cross-engine ABAC page: needs `scope=all-apis`, otherwise
   `403 Invalid scope, required scopes: unity-catalog`.
2. A Delta table with catalog commits is not readable through Iceberg REST
   ("not an Iceberg compatible table"); managed Iceberg or UniForm is needed for that path.
3. Delta + UC connector with `auth.type=oauth`: scan planning returns 401
   "Credential was not sent". With the workspace URL including the workspace ID (`/?o=<id>`): 404.
   A static OAuth access token works.
4. ABAC `CREATE POLICY ... EXCEPT \`admins\``: `PRINCIPAL_DOES_NOT_EXIST` (workspace-local group).
5. `DROP POLICY IF EXISTS` is a syntax error.
6. EMR Serverless docs give `/usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar`; on
   `emr-spark-8.1.0` that file does not exist (`NoSuchFileException`). Iceberg is on the default classpath.
7. EMR Serverless without a VPC cannot reach the Databricks host: every query hung ~400 s and the
   job hit its timeout. A VPC with private subnets and a NAT gateway fixed it.
