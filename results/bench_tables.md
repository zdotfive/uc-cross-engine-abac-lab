
### Local Spark 4.0.4, Delta + UC connector (static token), reader

| Table | Rows (count) | Countries | email/iban | Session start (s) | First query (s) | Warm median (s) | Warm min-max (s) |
|---|---|---|---|---|---|---|---|
| `customers_small_delta` | 250 | IT | masked (****) | 5.4 | 6.68 | 3.19 | 3.06-3.42 |
| `customers_small_uniform` | 250 | IT | masked (****) | 4.8 | 11.17 | 3.18 | 3.07-3.39 |
| `customers_small_delta_abac` | 250 | IT | masked (****) | 5.1 | 10.64 | 3.12 | 3.02-3.25 |
| `customers_small_uniform_abac` | 250 | IT | masked (****) | 4.7 | 10.74 | 3.11 | 3.06-3.27 |
| `customers_big_delta` | 2,500,000 | IT | masked (****) | 5.0 | 12.12 | 3.19 | 3.09-3.72 |
| `customers_big_uniform` | 2,500,000 | IT | masked (****) | 4.9 | 11.12 | 3.36 | 3.17-3.77 |
| `customers_big_delta_abac` | 2,500,000 | IT | masked (****) | 5.2 | 12.88 | 3.35 | 2.96-3.72 |
| `customers_big_uniform_abac` | 2,500,000 | IT | masked (****) | 4.8 | 11.18 | 3.26 | 2.99-3.65 |

Queries: 96 ok, 0 errors, 0 violations. First query = q1 (GROUP BY country), first run on that table. Warm = runs 2-3 of q1-q4.

### Local Spark 4.0.4, Iceberg REST, reader

| Table | Rows (count) | Countries | email/iban | Session start (s) | First query (s) | Warm median (s) | Warm min-max (s) |
|---|---|---|---|---|---|---|---|
| `customers_small_ice` | 250 | IT | masked (****) | 3.2 | 12.60 | 1.75 | 1.13-2.28 |
| `customers_small_uniform` | 250 | IT | masked (****) | 2.6 | 10.46 | 1.55 | 1.17-1.76 |
| `customers_small_ice_abac` | 250 | IT | masked (****) | 2.8 | 10.99 | 1.63 | 1.11-1.82 |
| `customers_small_uniform_abac` | 250 | IT | masked (****) | 2.7 | 10.44 | 1.57 | 1.02-1.94 |
| `customers_big_ice` | 2,500,000 | IT | masked (****) | 2.8 | 10.53 | 1.75 | 1.06-2.06 |
| `customers_big_uniform` | 2,500,000 | IT | masked (****) | 2.8 | 10.63 | 1.65 | 1.10-2.10 |
| `customers_big_ice_abac` | 2,500,000 | IT | masked (****) | 2.9 | 10.56 | 1.66 | 1.01-2.19 |
| `customers_big_uniform_abac` | 2,500,000 | IT | masked (****) | 2.7 | 10.01 | 1.56 | 0.96-1.96 |

Queries: 96 ok, 0 errors, 0 violations. First query = q1 (GROUP BY country), first run on that table. Warm = runs 2-3 of q1-q4.

### SQL warehouse, admin

| Table | Rows (count) | Countries | email/iban | Session start (s) | First query (s) | Warm median (s) | Warm min-max (s) |
|---|---|---|---|---|---|---|---|
| `customers_small_delta` | 1,000 | DE,ES,FR,IT | clear text | 1.0 | 0.53 | 0.48 | 0.46-0.64 |
| `customers_small_ice` | 1,000 | DE,ES,FR,IT | clear text | 0.9 | 0.50 | 0.45 | 0.43-0.48 |
| `customers_small_uniform` | 1,000 | DE,ES,FR,IT | clear text | 0.9 | 0.47 | 0.46 | 0.43-0.52 |
| `customers_small_delta_abac` | 1,000 | DE,ES,FR,IT | clear text | 1.0 | 0.44 | 0.30 | 0.28-0.35 |
| `customers_small_ice_abac` | 1,000 | DE,ES,FR,IT | clear text | 0.9 | 0.32 | 0.30 | 0.29-0.35 |
| `customers_small_uniform_abac` | 1,000 | DE,ES,FR,IT | clear text | 0.9 | 0.32 | 0.30 | 0.28-0.35 |
| `customers_big_delta` | 10,000,000 | DE,ES,FR,IT | clear text | 0.9 | 0.53 | 0.47 | 0.45-0.52 |
| `customers_big_ice` | 10,000,000 | DE,ES,FR,IT | clear text | 0.9 | 0.53 | 0.45 | 0.42-0.49 |
| `customers_big_uniform` | 10,000,000 | DE,ES,FR,IT | clear text | 0.9 | 0.52 | 0.47 | 0.44-0.57 |
| `customers_big_delta_abac` | 10,000,000 | DE,ES,FR,IT | clear text | 0.9 | 0.38 | 0.32 | 0.29-0.34 |
| `customers_big_ice_abac` | 10,000,000 | DE,ES,FR,IT | clear text | 1.0 | 0.52 | 0.34 | 0.32-0.36 |
| `customers_big_uniform_abac` | 10,000,000 | DE,ES,FR,IT | clear text | 0.9 | 0.38 | 0.34 | 0.30-0.45 |

Queries: 144 ok, 0 errors, 0 violations. First query = q1 (GROUP BY country), first run on that table. Warm = runs 2-3 of q1-q4.

### SQL warehouse, reader

| Table | Rows (count) | Countries | email/iban | Session start (s) | First query (s) | Warm median (s) | Warm min-max (s) |
|---|---|---|---|---|---|---|---|
| `customers_small_delta` | 250 | IT | masked (****) | 1.7 | 0.50 | 0.42 | 0.38-0.55 |
| `customers_small_ice` | 250 | IT | masked (****) | 1.3 | 0.47 | 0.43 | 0.39-0.63 |
| `customers_small_uniform` | 250 | IT | masked (****) | 1.5 | 0.56 | 0.43 | 0.38-0.47 |
| `customers_small_delta_abac` | 250 | IT | masked (****) | 1.6 | 0.45 | 0.41 | 0.40-0.44 |
| `customers_small_ice_abac` | 250 | IT | masked (****) | 1.3 | 0.43 | 0.41 | 0.34-0.44 |
| `customers_small_uniform_abac` | 250 | IT | masked (****) | 1.4 | 0.48 | 0.40 | 0.34-0.43 |
| `customers_big_delta` | 2,500,000 | IT | masked (****) | 1.4 | 0.50 | 0.45 | 0.38-0.48 |
| `customers_big_ice` | 2,500,000 | IT | masked (****) | 1.3 | 0.52 | 0.47 | 0.37-0.48 |
| `customers_big_uniform` | 2,500,000 | IT | masked (****) | 1.3 | 0.51 | 0.45 | 0.38-0.53 |
| `customers_big_delta_abac` | 2,500,000 | IT | masked (****) | 1.5 | 0.57 | 0.44 | 0.36-0.51 |
| `customers_big_ice_abac` | 2,500,000 | IT | masked (****) | 1.5 | 0.49 | 0.44 | 0.37-0.47 |
| `customers_big_uniform_abac` | 2,500,000 | IT | masked (****) | 1.3 | 0.48 | 0.44 | 0.35-0.48 |

Queries: 144 ok, 0 errors, 0 violations. First query = q1 (GROUP BY country), first run on that table. Warm = runs 2-3 of q1-q4.

### EMR Serverless, Iceberg REST, reader

Spark session start (once for all tables): 12.5 s

| Table | Rows (count) | Countries | email/iban | Session start (s) | First query (s) | Warm median (s) | Warm min-max (s) |
|---|---|---|---|---|---|---|---|
| `customers_small_ice` | 250 | IT | masked (****) | - | 29.92 | 1.36 | 1.12-3.22 |
| `customers_small_uniform` | 250 | IT | masked (****) | - | 2.10 | 1.16 | 1.02-1.32 |
| `customers_small_ice_abac` | 250 | IT | masked (****) | - | 1.77 | 1.04 | 0.94-1.17 |
| `customers_small_uniform_abac` | 250 | IT | masked (****) | - | 1.70 | 1.00 | 0.87-1.21 |
| `customers_big_ice` | 2,500,000 | IT | masked (****) | - | 1.94 | 1.07 | 0.90-1.37 |
| `customers_big_uniform` | 2,500,000 | IT | masked (****) | - | 1.72 | 1.00 | 0.83-1.14 |
| `customers_big_ice_abac` | 2,500,000 | IT | masked (****) | - | 1.59 | 1.04 | 0.86-1.31 |
| `customers_big_uniform_abac` | 2,500,000 | IT | masked (****) | - | 1.49 | 0.96 | 0.78-1.09 |

Queries: 96 ok, 0 errors, 0 violations. First query = q1 (GROUP BY country), first run on that table. Warm = runs 2-3 of q1-q4.
