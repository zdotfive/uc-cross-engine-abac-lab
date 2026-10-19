-- Cross-engine ABAC cost (run the day after the lab).
SELECT max(usage_date) AS last_usage_date FROM system.billing.usage;
SELECT usage_date, sku_name, identity_metadata.run_as AS run_as, SUM(usage_quantity) AS dbu
FROM system.billing.usage
WHERE usage_date >= '2026-10-19' AND billing_origin_product = 'EXTERNAL_COMPATIBILITY'
GROUP BY 1, 2, 3 ORDER BY 1;
SELECT usage_date, billing_origin_product, round(SUM(usage_quantity), 6) AS dbu
FROM system.billing.usage WHERE usage_date >= '2026-10-19' GROUP BY 1, 2 ORDER BY 1, 2;
