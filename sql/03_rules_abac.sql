-- ABAC with governed tags on the *_abac tables. Run as admin after 01_setup.sql.
-- Policies target only the reader (TO). `EXCEPT `admins`` is rejected: admins is a
-- workspace-local group and policies need account principals (PRINCIPAL_DOES_NOT_EXIST).
-- Tag keys are prefixed with xabac_ because governed tags live at account level.

CREATE GOVERNED TAG xabac_pii     DESCRIPTION 'Lab: personal data column' VALUES ('email', 'iban');
CREATE GOVERNED TAG xabac_country DESCRIPTION 'Lab: column used for the country row filter';
CREATE GOVERNED TAG xabac_abac    DESCRIPTION 'Lab: table governed by ABAC policies';

ALTER TABLE labs.xabac_lab.customers_small_delta_abac SET TAGS ('xabac_abac');
ALTER TABLE labs.xabac_lab.customers_small_delta_abac ALTER COLUMN email   SET TAGS ('xabac_pii' = 'email');
ALTER TABLE labs.xabac_lab.customers_small_delta_abac ALTER COLUMN iban    SET TAGS ('xabac_pii' = 'iban');
ALTER TABLE labs.xabac_lab.customers_small_delta_abac ALTER COLUMN country SET TAGS ('xabac_country');
ALTER TABLE labs.xabac_lab.customers_small_ice_abac SET TAGS ('xabac_abac');
ALTER TABLE labs.xabac_lab.customers_small_ice_abac ALTER COLUMN email   SET TAGS ('xabac_pii' = 'email');
ALTER TABLE labs.xabac_lab.customers_small_ice_abac ALTER COLUMN iban    SET TAGS ('xabac_pii' = 'iban');
ALTER TABLE labs.xabac_lab.customers_small_ice_abac ALTER COLUMN country SET TAGS ('xabac_country');
ALTER TABLE labs.xabac_lab.customers_small_uniform_abac SET TAGS ('xabac_abac');
ALTER TABLE labs.xabac_lab.customers_small_uniform_abac ALTER COLUMN email   SET TAGS ('xabac_pii' = 'email');
ALTER TABLE labs.xabac_lab.customers_small_uniform_abac ALTER COLUMN iban    SET TAGS ('xabac_pii' = 'iban');
ALTER TABLE labs.xabac_lab.customers_small_uniform_abac ALTER COLUMN country SET TAGS ('xabac_country');
ALTER TABLE labs.xabac_lab.customers_big_delta_abac SET TAGS ('xabac_abac');
ALTER TABLE labs.xabac_lab.customers_big_delta_abac ALTER COLUMN email   SET TAGS ('xabac_pii' = 'email');
ALTER TABLE labs.xabac_lab.customers_big_delta_abac ALTER COLUMN iban    SET TAGS ('xabac_pii' = 'iban');
ALTER TABLE labs.xabac_lab.customers_big_delta_abac ALTER COLUMN country SET TAGS ('xabac_country');
ALTER TABLE labs.xabac_lab.customers_big_ice_abac SET TAGS ('xabac_abac');
ALTER TABLE labs.xabac_lab.customers_big_ice_abac ALTER COLUMN email   SET TAGS ('xabac_pii' = 'email');
ALTER TABLE labs.xabac_lab.customers_big_ice_abac ALTER COLUMN iban    SET TAGS ('xabac_pii' = 'iban');
ALTER TABLE labs.xabac_lab.customers_big_ice_abac ALTER COLUMN country SET TAGS ('xabac_country');
ALTER TABLE labs.xabac_lab.customers_big_uniform_abac SET TAGS ('xabac_abac');
ALTER TABLE labs.xabac_lab.customers_big_uniform_abac ALTER COLUMN email   SET TAGS ('xabac_pii' = 'email');
ALTER TABLE labs.xabac_lab.customers_big_uniform_abac ALTER COLUMN iban    SET TAGS ('xabac_pii' = 'iban');
ALTER TABLE labs.xabac_lab.customers_big_uniform_abac ALTER COLUMN country SET TAGS ('xabac_country');

CREATE POLICY xabac_mask_pii
ON SCHEMA labs.xabac_lab
COMMENT 'Mask every column tagged xabac_pii'
COLUMN MASK labs.xabac_lab.mask_star
TO `${READER_APP_ID}`
FOR TABLES
WHEN has_tag('xabac_abac')
MATCH COLUMNS has_tag('xabac_pii') AS pii
ON COLUMN pii;

CREATE POLICY xabac_only_it
ON SCHEMA labs.xabac_lab
COMMENT 'Keep only IT rows'
ROW FILTER labs.xabac_lab.is_it
TO `${READER_APP_ID}`
FOR TABLES
WHEN has_tag('xabac_abac')
MATCH COLUMNS has_tag('xabac_country') AS ctry
USING COLUMNS (ctry);

SHOW POLICIES ON SCHEMA labs.xabac_lab;
