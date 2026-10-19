-- Classic rules on the non-ABAC tables, then grants for the reader (${READER_APP_ID}).
ALTER TABLE labs.xabac_lab.customers_small_delta SET ROW FILTER labs.xabac_lab.only_it ON (country);
ALTER TABLE labs.xabac_lab.customers_small_delta ALTER COLUMN email SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_small_delta ALTER COLUMN iban  SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_small_ice SET ROW FILTER labs.xabac_lab.only_it ON (country);
ALTER TABLE labs.xabac_lab.customers_small_ice ALTER COLUMN email SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_small_ice ALTER COLUMN iban  SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_small_uniform SET ROW FILTER labs.xabac_lab.only_it ON (country);
ALTER TABLE labs.xabac_lab.customers_small_uniform ALTER COLUMN email SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_small_uniform ALTER COLUMN iban  SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_big_delta SET ROW FILTER labs.xabac_lab.only_it ON (country);
ALTER TABLE labs.xabac_lab.customers_big_delta ALTER COLUMN email SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_big_delta ALTER COLUMN iban  SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_big_ice SET ROW FILTER labs.xabac_lab.only_it ON (country);
ALTER TABLE labs.xabac_lab.customers_big_ice ALTER COLUMN email SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_big_ice ALTER COLUMN iban  SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_big_uniform SET ROW FILTER labs.xabac_lab.only_it ON (country);
ALTER TABLE labs.xabac_lab.customers_big_uniform ALTER COLUMN email SET MASK labs.xabac_lab.mask_pii;
ALTER TABLE labs.xabac_lab.customers_big_uniform ALTER COLUMN iban  SET MASK labs.xabac_lab.mask_pii;

GRANT USE CATALOG          ON CATALOG labs             TO `${READER_APP_ID}`;
GRANT USE SCHEMA           ON SCHEMA  labs.xabac_lab   TO `${READER_APP_ID}`;
GRANT SELECT               ON SCHEMA  labs.xabac_lab   TO `${READER_APP_ID}`;
GRANT EXECUTE              ON SCHEMA  labs.xabac_lab   TO `${READER_APP_ID}`;
GRANT EXTERNAL USE SCHEMA  ON SCHEMA  labs.xabac_lab   TO `${READER_APP_ID}`;
