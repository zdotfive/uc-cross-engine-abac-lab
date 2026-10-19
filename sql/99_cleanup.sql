-- Removes everything created by the lab. Policies first, then tables, functions, schema, tags.
-- DROP POLICY has no IF EXISTS (PARSE_SYNTAX_ERROR). DROP SCHEMA ... CASCADE also removes schema-level policies.
DROP POLICY xabac_mask_pii ON SCHEMA labs.xabac_lab;
DROP POLICY xabac_only_it  ON SCHEMA labs.xabac_lab;
DROP SCHEMA IF EXISTS labs.xabac_lab CASCADE;
REVOKE USE CATALOG ON CATALOG labs FROM `${READER_APP_ID}`;
DROP GOVERNED TAG xabac_pii;
DROP GOVERNED TAG xabac_country;
DROP GOVERNED TAG xabac_abac;
