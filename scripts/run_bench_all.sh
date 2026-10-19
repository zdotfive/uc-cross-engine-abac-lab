#!/usr/bin/env bash
# Full local benchmark, sequential. Needs Java 17+ in JAVA_HOME for Spark.
set -uo pipefail
cd "$(dirname "$0")/.."
PY=.venv/bin/python
ALL=""; ICE=""; DLT=""
for s in small big; do for a in "" _abac; do
  ALL+="customers_${s}_delta${a},customers_${s}_ice${a},customers_${s}_uniform${a},"
  ICE+="customers_${s}_ice${a},customers_${s}_uniform${a},"
  DLT+="customers_${s}_delta${a},customers_${s}_uniform${a},"
done; done
$PY scripts/bench.py --engine warehouse --principal admin  --tables "${ALL%,}" || exit $?
$PY scripts/bench.py --engine warehouse --principal reader --tables "${ALL%,}" || exit $?
$PY scripts/bench.py --engine iceberg   --principal reader --tables "${ICE%,}" || exit $?
$PY scripts/bench.py --engine delta     --principal reader --tables "${DLT%,}" || exit $?
echo BENCH_DONE
