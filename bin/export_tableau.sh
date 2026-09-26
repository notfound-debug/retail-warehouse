#!/usr/bin/env bash
# Export the two Tableau Public data sources from the report views:
#   tableau/revenue_trend.csv     <- v_rpt_monthly_revenue   (dashboard 1)
#   tableau/cohort_retention.csv  <- v_rpt_cohort_retention  (dashboard 2)
# Runs inside the tools container, after a load:
#   docker compose exec tools bin/export_tableau.sh
# Then in Tableau Public: Data > Refresh (see tableau/GUIDE.md).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p tableau
for name in revenue_trend cohort_retention; do
    bin/sql.sh "sql/export/$name.sql"
    # sqlplus CSV output starts with an empty line; remove it.
    sed -i '/^$/d' "tableau/$name.csv"
    echo "tableau/$name.csv: $(( $(wc -l < "tableau/$name.csv") - 1 )) rows"
done
