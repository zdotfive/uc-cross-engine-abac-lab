REVOKE MODIFY ON TABLE labs.xabac_lab.customers_small_ice      FROM `${READER_APP_ID}`;
REVOKE MODIFY ON TABLE labs.xabac_lab.customers_small_ice_abac FROM `${READER_APP_ID}`;
REVOKE MODIFY ON TABLE labs.xabac_lab.customers_small_delta    FROM `${READER_APP_ID}`;
SELECT 'ice' t, count(*) n, count_if(customer_id = 99999999) external_rows FROM labs.xabac_lab.customers_small_ice
UNION ALL SELECT 'ice_abac', count(*), count_if(customer_id = 99999999) FROM labs.xabac_lab.customers_small_ice_abac
UNION ALL SELECT 'delta', count(*), count_if(customer_id = 99999999) FROM labs.xabac_lab.customers_small_delta;
