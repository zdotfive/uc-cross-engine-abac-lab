-- Policy statements only (rerun after the EXCEPT `admins` failure).
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

DESCRIBE POLICY xabac_mask_pii ON SCHEMA labs.xabac_lab;
DESCRIBE POLICY xabac_only_it ON SCHEMA labs.xabac_lab;
