#!/usr/bin/env bash
# Generate the SCD2 customer delta extract: data/delta/customer_delta.csv
# (real address changes found in the Olist data; see sql/delta/make_customer_delta.sql).
# Runs inside the tools container, after a successful full load:
#   docker compose exec tools bin/make_delta.sh
# Then load it with:
#   docker compose exec tools bin/nightly_load.sh --delta
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p data/delta
bin/sql.sh sql/delta/make_customer_delta.sql

# sqlplus CSV output starts with an empty line. The external table skips exactly
# one line (the header), so an empty first line would make it read the header
# as a customer. Delete empty lines.
sed -i '/^$/d' data/delta/customer_delta.csv

rows=$(( $(wc -l < data/delta/customer_delta.csv) - 1 ))   # minus the header line
echo "Wrote data/delta/customer_delta.csv: $rows customers whose latest-order address differs from their first"
