# Lab log

Date: 2026-10-19. Databricks Free Edition workspace on AWS eu-west-1 (catalog `labs`, Serverless
Starter Warehouse). AWS account for EMR: a separate lab account, region eu-west-1.

Local tools: macOS, Python 3.14, `pyspark 4.0.4`, `duckdb 1.5.6` (extensions iceberg `890b78a9c`,
httpfs `4bc690d`, delta `6059958`), `databricks-sdk 0.153.0`, `databricks-sql-connector 4.6.0`,
OpenJDK 21.0.11, AWS CLI 2.22.30.

Principals:

- **admin**: workspace owner, member of the workspace group `admins`. Setup, checks, cleanup.
- **reader**: service principal `sp-xabac-reader`, OAuth M2M, not an admin. Every read below.

Identifiers (workspace host, AWS account, storage bucket, local host name, admin user) are replaced
with placeholders in the logs. Credentials are read from `.env` or AWS Secrets Manager and never
printed; all logs were scanned for the client secret and for token and AWS key patterns.

---

## 1. Setup

`scripts/create_reader_sp.sh` creates the reader and a 7-day OAuth secret and writes `.env`.
The first attempt created the service principal but lost the secret to a quoting bug in the
script; the fixed script was re-run against the same principal (`00_reader_sp.log`).

`sql/01_setup.sql` (log `01_setup.log`, 18 statements, 0 failed):

- schema `labs.xabac_lab`;
- functions: `mask_pii`, `only_it` (classic rules: exemption via `is_member('admins')`) and
  `mask_star`, `is_it` (ABAC: the policy decides who is affected, the function only transforms);
- `customers_{small,big}_delta`: Delta, `TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported')`,
  1,000 and 10,000,000 rows;
- `customers_{small,big}_ice`: `USING ICEBERG` (CTAS);
- `customers_{small,big}_uniform`: Delta with `catalogManaged`, `enableIcebergCompatV2`,
  `universalFormat.enabledFormats = 'iceberg'`, deletion vectors off;
- the same six again with the suffix `_abac`.

`information_schema.tables` lists the 12 tables as `MANAGED`, format `DELTA` or `ICEBERG`.

## 2. Rules

### Classic (`sql/02_rules_classic.sql`, log `02_rules_classic.log`, 23 statements, 0 failed)

```sql
ALTER TABLE <t> SET ROW FILTER labs.xabac_lab.only_it ON (country);
ALTER TABLE <t> ALTER COLUMN email SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE <t> ALTER COLUMN iban  SET MASK labs.xabac_lab.mask_pii;
```

on the six non-ABAC tables, plus the grants of step 3.

### ABAC (`sql/03_rules_abac.sql`, logs `03_rules_abac.log`, `03b_policies.log`)

Governed tags (account level, so prefixed): `xabac_pii` (values `email`, `iban`), `xabac_country`,
`xabac_abac`. `CREATE GOVERNED TAG` works on Free Edition. Tags set on the six `_abac` tables
(table: `xabac_abac`; columns: `email`, `iban`, `country`).

First attempt, with `EXCEPT \`admins\`` as in the docs' examples:

```
[PRINCIPAL_DOES_NOT_EXIST.PRINCIPAL_DOES_NOT_EXIST] Could not find principal with name admins.
```

`admins` is a workspace-local group; policies need account principals. The policies target only
the reader (`TO`), so the `EXCEPT` clause was dropped:

```sql
CREATE POLICY xabac_mask_pii ON SCHEMA labs.xabac_lab
COLUMN MASK labs.xabac_lab.mask_star
TO `<reader>`
FOR TABLES WHEN has_tag('xabac_abac')
MATCH COLUMNS has_tag('xabac_pii') AS pii ON COLUMN pii;

CREATE POLICY xabac_only_it ON SCHEMA labs.xabac_lab
ROW FILTER labs.xabac_lab.is_it
TO `<reader>`
FOR TABLES WHEN has_tag('xabac_abac')
MATCH COLUMNS has_tag('xabac_country') AS ctry USING COLUMNS (ctry);
```

Both `SUCCEEDED`; `SHOW POLICIES` and `DESCRIBE POLICY` list them.

### Check inside Databricks (`sql/04_check.sql`, logs `04_check_admin.log`, `04_check_reader.log`)

On all 12 tables: admin sees DE/ES/FR/IT with 250 each (small) or 2,500,000 each (big), clear
text email and iban. Reader sees only IT (250 / 2,500,000) and `****` in both columns.

## 3. Grants

```sql
GRANT USE CATALOG ON CATALOG labs TO `<reader>`;
GRANT USE SCHEMA, SELECT, EXECUTE, EXTERNAL USE SCHEMA ON SCHEMA labs.xabac_lab TO `<reader>`;
```

(five separate statements in `02_rules_classic.sql`, all `SUCCEEDED`).

## 4. Local Spark

Session config in `scripts/spark_session.py`.

**Iceberg REST** (`org.apache.iceberg:iceberg-spark-runtime-4.0_2.13:1.11.0` + `iceberg-aws-bundle`),
as on the cross-engine ABAC page, plus `spark.sql.catalog.labs.scope = all-apis`. Without the scope
the catalog answers `403 Invalid scope, required scopes: unity-catalog` (seen in the earlier check).

**Delta + UC connector** (`delta-spark_4.0_2.13:4.1.0`, `delta-iceberg_2.13:4.1.0`,
`unitycatalog-spark_2.13:0.4.0`, `hadoop-aws:3.4.1`, `ServerSidePlanning.enabled = true`).
`scripts/delta_auth_probe.py`, log `04_delta_auth_probe.log`:

| `auth` | `uri` | Result |
|---|---|---|
| `oauth` (docs) | workspace host | `Failed to plan table scan ... HTTP status: 401 ... "Credential was not sent or was of an unsupported type for this API."` |
| `oauth` (docs) | host + `/?o=<workspace-id>` | `Failed to plan table scan ... HTTP status: 404` |
| static token (reader's OAuth access token as `...labs.token`) | workspace host | `IT 250` |

The stack trace shows the planning call is made by
`org.apache.spark.sql.delta.serverSidePlanning.IcebergRESTCatalogPlanningClient.planScan`.

**Benchmark**: `scripts/run_bench_all.sh` -> `scripts/bench.py`. One process (fresh session) per
table; queries `q1` `GROUP BY country`, `q2` `email, iban LIMIT 5`, `q3` `count(*)`,
`q4` `sum(annual_spend)`; 3 runs each. Warehouse baseline uses the SQL connector with
`use_cached_result = false`. 520 measurements, 0 errors, 0 violations
(`bench/*.jsonl`, tables in `bench_tables.md`).

## 5. EMR Serverless

Commands: `emr/commands.sh` (`create`, `upload`, `network-create`, `run`, `wait`, `fetch`,
`delete`, `network-delete`). Job: `emr/emr_bench.py`. Release `emr-spark-8.1.0`
(Spark `4.1.1-amzn-0`, Iceberg 1.11.0-amzn), region eu-west-1 (same as the data).
Max capacity 8 vCPU / 32 GB, auto-stop after 5 minutes. The reader's client id and secret are in
Secrets Manager (`xabac-lab/reader`) and read by the job at runtime; the job role can read only
that secret and the lab bucket.

| Run | Config | Outcome | Duration | Billed |
|---|---|---|---|---|
| 1 | `--jars /usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar` (EMR Serverless docs), no VPC | `FAILED`: `java.nio.file.NoSuchFileException: /usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar` | 11 s | 0.033 vCPU-h, 0.083 GB-h |
| 2 | no `--jars` (Iceberg is on the default classpath), no VPC | `CANCELLED` at the 45 min timeout. Every query: `RESTException: Error occurred while processing POST request` after ~400 s | 2,708 s | 4.504 vCPU-h, 11.26 GB-h |
| 3 | no `--jars`, VPC with 2 private subnets + NAT gateway + S3 gateway endpoint | `SUCCESS` | 173 s | 0.273 vCPU-h, 0.683 GB-h (storage 2.733 GB-h, billed 0) |

Run 2: without VPC configuration EMR Serverless reaches only some AWS services in the same Region
(Secrets Manager worked), not the Databricks host.

Run 3 (`emr/emr_bench.jsonl`): 96 queries, 0 errors, 0 violations; IT only, `****`. Spark session
start 12.5 s; first query of the job 29.92 s; first query on each following table 1.49-2.10 s;
warm medians 0.96-1.36 s.

Logs: `emr/01_create.log` ... `emr/06_network_delete.log`, driver logs `emr/driver_*.gz` (run 3).

## 6. DuckDB

`scripts/duckdb_check.py`, log `06_duckdb.log`.

- `loadTable` on the 8 Iceberg-readable tables, with or without
  `X-Iceberg-Access-Delegation: vended-credentials`: HTTP 200,
  `config={'scan-planning-mode': 'server'}`, 0 storage credentials. On the 4 plain Delta tables:
  400 "is not an Iceberg compatible table".
- `ATTACH 'labs' AS uc (TYPE iceberg, ..., DEFAULT_REGION 'eu-west-1')` succeeds; every `SELECT`
  fails: Iceberg-readable tables with `HTTP GET error reading '.../snap-...avro' ... (HTTP 403 Forbidden)`,
  Delta tables with the 400 above.
- `temporary-table-credentials` READ: 400 `ROW_COLUMN_ACCESS_POLICIES_NOT_SUPPORTED_ON_ASSIGNED_CLUSTERS`
  (classic) and 403 `ABAC policies can only be called with permission enforcing scope` (ABAC).
  `delta_scan` was never reached.

No data returned on any of the 12 tables.

## 7. Bypass attempts

`scripts/bypass_probe.py` (log `07_bypass.log`; the first attempt `07_bypass_first_attempt.log`
crashed while decoding a signed S3 response and was replaced by a `HeadObject`, see below).

1. `temporary-table-credentials` READ / READ_WRITE: see SUMMARY table; nothing issued.
2. `temporary-path-credentials` (`PATH_READ`) on the table location: 403
   `User does not have EXTERNAL USE LOCATION on External Location '<...>'`.
3. Files named in the Iceberg metadata (metadata JSON, manifest list): unsigned GET -> 403
   `AccessDenied`. A signed request with an IAM identity of the AWS account that owns the
   workspace storage bucket succeeds (`HeadObject` returned the size; the first attempt with
   `s3 cp` returned file bytes). That identity is outside Unity Catalog.
4. `loadTable` with vended-credentials delegation: `storage-credentials: []`.
5. Server-side scan plan (`POST .../tables/<t>/plan`, `07_bypass_plan.log`, `07_plan_size.log`):
   `status: completed`, one `file-scan-task` pointing to a Parquet file under a different table id
   (the filtered, masked result), and storage credentials for that prefix only.
   Small table: 250 records, 5,576 bytes. Big table: 2,500,000 records, 22,833,503 bytes;
   the plan call took 6.2 s (`_ice`) and 0.84 s (`_uniform`).

External write (`scripts/spark_write_probe.py`, logs `07_write_probe*.log`), INSERT of one DE row:

| Path | Without `MODIFY` | With temporary `MODIFY` |
|---|---|---|
| Iceberg REST | fails; root cause `Unable to load credentials from any of the providers in the chain` (no write credentials vended) | same |
| Delta + UC connector | `UNSUPPORTED_FEATURE.TABLE_OPERATION ... does not support append in batch mode` | same |

`MODIFY` was granted on three small tables and revoked right after. Admin count afterwards:
1,000 rows and 0 external rows on each.

## 8. Cost

`sql/08_billing.sql`, log `08_billing_day0.log` (read on 2026-10-19 in the evening):

```
2026-10-19 | PREMIUM_JOBS_SERVERLESS_COMPUTE_EUROPE_IRELAND | <lab reader>    | 1.622916359999999910
2026-10-19 | PREMIUM_JOBS_SERVERLESS_COMPUTE_EUROPE_IRELAND | <earlier check> | 0.373616186666666590
EXTERNAL_COMPATIBILITY total for the day: 1.996533 DBU
```

List price (`sql/08b_list_price.sql`): 0.39 USD per DBU for that SKU.

Re-check on the next day: pending.

## 9. Cleanup

Databricks (`sql/99_cleanup.sql`, log `09_cleanup.log`): `DROP POLICY IF EXISTS` is a
`PARSE_SYNTAX_ERROR`; `DROP SCHEMA ... CASCADE` removed tables, functions and the schema-level
policies (`information_schema.abac_policy_definitions`: 0 rows for `xabac%`). Catalog grant revoked,
governed tags dropped, service principal deleted. Verified: schema absent, no grants, no principal.

AWS (`emr/05_delete.log`, `emr/06_network_delete.log`): application, secret (no recovery window),
IAM role and policy, bucket, NAT gateway (`deleted`), Elastic IP, S3 endpoint, internet gateway,
subnets, route tables, security group and VPC deleted; the listings afterwards are empty.
