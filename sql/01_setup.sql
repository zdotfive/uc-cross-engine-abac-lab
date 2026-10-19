-- Schema, rule functions and tables. Run as admin before 02_rules.sql.
-- Tables are created and filled before any rule is attached, so CTAS copies see all rows.

CREATE SCHEMA IF NOT EXISTS labs.xabac_lab COMMENT 'Cross-engine row filters, column masks and ABAC';

-- Classic rules: the function decides who is exempt
CREATE OR REPLACE FUNCTION labs.xabac_lab.mask_pii(v STRING) RETURNS STRING
RETURN CASE WHEN is_member('admins') THEN v ELSE '****' END;
CREATE OR REPLACE FUNCTION labs.xabac_lab.only_it(c STRING) RETURNS BOOLEAN
RETURN is_member('admins') OR c = 'IT';

-- ABAC rules: the policy decides who is affected (TO ... EXCEPT ...), the function only transforms
CREATE OR REPLACE FUNCTION labs.xabac_lab.mask_star(v STRING) RETURNS STRING RETURN '****';
CREATE OR REPLACE FUNCTION labs.xabac_lab.is_it(c STRING) RETURNS BOOLEAN RETURN c = 'IT';

-- customers_small_delta: 1000 rows, a quarter per country
CREATE TABLE labs.xabac_lab.customers_small_delta
USING DELTA
TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported')
AS SELECT
  id + 1                                                     AS customer_id,
  concat('Customer ', lpad(CAST(id + 1 AS STRING), 8, '0'))  AS full_name,
  concat('customer', id + 1, '@example.com')                 AS email,
  concat(element_at(array('IT','DE','FR','ES'), CAST(id % 4 AS INT) + 1),
         '00X', lpad(CAST(id * 7919 % 100000000 AS STRING), 20, '0')) AS iban,
  element_at(array('IT','DE','FR','ES'), CAST(id % 4 AS INT) + 1)     AS country,
  CAST(100 + (id * 37 % 9900) AS DECIMAL(10,2))              AS annual_spend
FROM range(1000);

CREATE TABLE labs.xabac_lab.customers_small_ice
USING ICEBERG
AS SELECT * FROM labs.xabac_lab.customers_small_delta;

CREATE TABLE labs.xabac_lab.customers_small_uniform
USING DELTA
TBLPROPERTIES (
  'delta.feature.catalogManaged' = 'supported',
  'delta.enableDeletionVectors' = 'false',
  'delta.enableIcebergCompatV2' = 'true',
  'delta.universalFormat.enabledFormats' = 'iceberg')
AS SELECT * FROM labs.xabac_lab.customers_small_delta;

CREATE TABLE labs.xabac_lab.customers_small_delta_abac
USING DELTA
TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported')
AS SELECT * FROM labs.xabac_lab.customers_small_delta;

CREATE TABLE labs.xabac_lab.customers_small_ice_abac
USING ICEBERG
AS SELECT * FROM labs.xabac_lab.customers_small_delta;

CREATE TABLE labs.xabac_lab.customers_small_uniform_abac
USING DELTA
TBLPROPERTIES (
  'delta.feature.catalogManaged' = 'supported',
  'delta.enableDeletionVectors' = 'false',
  'delta.enableIcebergCompatV2' = 'true',
  'delta.universalFormat.enabledFormats' = 'iceberg')
AS SELECT * FROM labs.xabac_lab.customers_small_delta;

-- customers_big_delta: 10000000 rows, a quarter per country
CREATE TABLE labs.xabac_lab.customers_big_delta
USING DELTA
TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported')
AS SELECT
  id + 1                                                     AS customer_id,
  concat('Customer ', lpad(CAST(id + 1 AS STRING), 8, '0'))  AS full_name,
  concat('customer', id + 1, '@example.com')                 AS email,
  concat(element_at(array('IT','DE','FR','ES'), CAST(id % 4 AS INT) + 1),
         '00X', lpad(CAST(id * 7919 % 100000000 AS STRING), 20, '0')) AS iban,
  element_at(array('IT','DE','FR','ES'), CAST(id % 4 AS INT) + 1)     AS country,
  CAST(100 + (id * 37 % 9900) AS DECIMAL(10,2))              AS annual_spend
FROM range(10000000);

CREATE TABLE labs.xabac_lab.customers_big_ice
USING ICEBERG
AS SELECT * FROM labs.xabac_lab.customers_big_delta;

CREATE TABLE labs.xabac_lab.customers_big_uniform
USING DELTA
TBLPROPERTIES (
  'delta.feature.catalogManaged' = 'supported',
  'delta.enableDeletionVectors' = 'false',
  'delta.enableIcebergCompatV2' = 'true',
  'delta.universalFormat.enabledFormats' = 'iceberg')
AS SELECT * FROM labs.xabac_lab.customers_big_delta;

CREATE TABLE labs.xabac_lab.customers_big_delta_abac
USING DELTA
TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported')
AS SELECT * FROM labs.xabac_lab.customers_big_delta;

CREATE TABLE labs.xabac_lab.customers_big_ice_abac
USING ICEBERG
AS SELECT * FROM labs.xabac_lab.customers_big_delta;

CREATE TABLE labs.xabac_lab.customers_big_uniform_abac
USING DELTA
TBLPROPERTIES (
  'delta.feature.catalogManaged' = 'supported',
  'delta.enableDeletionVectors' = 'false',
  'delta.enableIcebergCompatV2' = 'true',
  'delta.universalFormat.enabledFormats' = 'iceberg')
AS SELECT * FROM labs.xabac_lab.customers_big_delta;

SELECT table_name, table_type, data_source_format
FROM labs.information_schema.tables WHERE table_schema = 'xabac_lab' ORDER BY table_name;
