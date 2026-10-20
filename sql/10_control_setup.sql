-- Control for the DuckDB result: a reader with the same grants as in the lab, tables WITHOUT rules
-- in all three layouts (Delta, managed Iceberg, Delta + UniForm) next to one table with rules.
CREATE SCHEMA IF NOT EXISTS ${CATALOG}.xabac_ctrl COMMENT 'Control: DuckDB on tables with and without rules';
CREATE OR REPLACE FUNCTION ${CATALOG}.xabac_ctrl.mask_pii(v STRING) RETURNS STRING
RETURN CASE WHEN is_member('admins') THEN v ELSE '****' END;
CREATE OR REPLACE FUNCTION ${CATALOG}.xabac_ctrl.only_it(c STRING) RETURNS BOOLEAN
RETURN is_member('admins') OR c = 'IT';
CREATE TABLE ${CATALOG}.xabac_ctrl.ctrl_delta_plain USING DELTA AS SELECT
  id + 1 AS customer_id, concat('Customer ', lpad(CAST(id + 1 AS STRING), 8, '0')) AS full_name,
  concat('customer', id + 1, '@example.com') AS email,
  concat(element_at(array('IT','DE','FR','ES'), CAST(id % 4 AS INT) + 1), '00X',
         lpad(CAST(id * 7919 % 100000000 AS STRING), 20, '0')) AS iban,
  element_at(array('IT','DE','FR','ES'), CAST(id % 4 AS INT) + 1) AS country,
  CAST(100 + (id * 37 % 9900) AS DECIMAL(10,2)) AS annual_spend
FROM range(1000);
CREATE TABLE ${CATALOG}.xabac_ctrl.ctrl_delta_cm USING DELTA
TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported')
AS SELECT * FROM ${CATALOG}.xabac_ctrl.ctrl_delta_plain;
CREATE TABLE ${CATALOG}.xabac_ctrl.ctrl_uniform USING DELTA
TBLPROPERTIES (
  'delta.feature.catalogManaged' = 'supported',
  'delta.enableDeletionVectors' = 'false',
  'delta.enableIcebergCompatV2' = 'true',
  'delta.universalFormat.enabledFormats' = 'iceberg')
AS SELECT * FROM ${CATALOG}.xabac_ctrl.ctrl_delta_plain;
CREATE TABLE ${CATALOG}.xabac_ctrl.ctrl_ice USING ICEBERG AS SELECT * FROM ${CATALOG}.xabac_ctrl.ctrl_delta_plain;
CREATE TABLE ${CATALOG}.xabac_ctrl.ctrl_ice_rules USING ICEBERG AS SELECT * FROM ${CATALOG}.xabac_ctrl.ctrl_delta_plain;
ALTER TABLE ${CATALOG}.xabac_ctrl.ctrl_ice_rules SET ROW FILTER ${CATALOG}.xabac_ctrl.only_it ON (country);
ALTER TABLE ${CATALOG}.xabac_ctrl.ctrl_ice_rules ALTER COLUMN email SET MASK ${CATALOG}.xabac_ctrl.mask_pii;
ALTER TABLE ${CATALOG}.xabac_ctrl.ctrl_ice_rules ALTER COLUMN iban  SET MASK ${CATALOG}.xabac_ctrl.mask_pii;
GRANT USE CATALOG         ON CATALOG ${CATALOG}            TO `${READER_APP_ID}`;
GRANT USE SCHEMA          ON SCHEMA  ${CATALOG}.xabac_ctrl TO `${READER_APP_ID}`;
GRANT SELECT              ON SCHEMA  ${CATALOG}.xabac_ctrl TO `${READER_APP_ID}`;
GRANT EXECUTE             ON SCHEMA  ${CATALOG}.xabac_ctrl TO `${READER_APP_ID}`;
GRANT EXTERNAL USE SCHEMA ON SCHEMA  ${CATALOG}.xabac_ctrl TO `${READER_APP_ID}`;
