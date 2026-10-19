-- Temporary MODIFY for the external write test (revoked by 05_write_revoke.sql).
GRANT MODIFY ON TABLE labs.xabac_lab.customers_small_ice      TO `${READER_APP_ID}`;
GRANT MODIFY ON TABLE labs.xabac_lab.customers_small_ice_abac TO `${READER_APP_ID}`;
GRANT MODIFY ON TABLE labs.xabac_lab.customers_small_delta    TO `${READER_APP_ID}`;
