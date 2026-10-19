SELECT sku_name, currency_code, usage_unit, pricing.default AS list_price, price_start_time, price_end_time
FROM system.billing.list_prices
WHERE sku_name = 'PREMIUM_JOBS_SERVERLESS_COMPUTE_EUROPE_IRELAND'
ORDER BY price_start_time DESC LIMIT 3;
