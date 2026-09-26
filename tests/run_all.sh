#!/usr/bin/env bash
# =============================================================================
# tests/run_all.sh: end-to-end test of the whole pipeline, starting from an
# empty schema. Runs inside the tools container:
#
#   docker compose exec tools tests/run_all.sh
#
# WARNING: it drops and rebuilds every object in the DW schema, so all
# warehouse data is replaced. It ends with a fully loaded warehouse (full
# load + customer delta).
#
# What is verified (each line prints PASS or FAIL):
#   1  schema        1 fact + 5 dimensions, keys, bitmap indexes, date dimension, packages, 12 views
#   2  full load     row counts and price total match the source files
#   3  rerun         idempotency (nothing changes), stale-lock recovery, log rotation
#   4  lock          a live lock makes the wrapper skip without touching the database
#   5  bad rows      a broken input file: exactly the bad rows are logged and skipped
#   6  bad step      a missing input file: batch FAILED, error logged, exit code 1
#   7  SCD2          delta extract closes and re-versions exactly the changed customers
#   8  abandoned     a batch left RUNNING is marked FAILED by the next run
#   9  views         all 12 report views return rows
#  10  arguments     bad arguments are rejected
#  11  exports       the two Tableau CSVs match their views and the warehouse totals
#  12  integration   read-only reporting user sees only the views; pre-load check gates the load
# Exit code: 0 if every check passed, 1 otherwise.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/usr/local/bin:$PATH"

PASSED=0
FAILED=0

section() { echo; echo "=== $*"; }

# check "what is being checked" "actual value" "expected value"
check() {
    if [ "$2" = "$3" ]; then
        PASSED=$((PASSED + 1))
        printf '  PASS  %s\n' "$1"
    else
        FAILED=$((FAILED + 1))
        printf '  FAIL  %s  (expected [%s], got [%s])\n' "$1" "$3" "$2"
    fi
}

# Run one SQL query that returns a single value; print it without spaces.
sql_value() {
    bin/sql.sh -c "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 32767
$1;" | tr -d '[:space:]'
}

# Run the nightly wrapper with the given arguments; print only its exit code.
load() {
    bin/nightly_load.sh "$@" > /dev/null
    echo $?
}

latest_log()   { ls -1t logs/nightly/nightly_*.log | head -1; }
last_batch()   { sql_value "SELECT MAX(batch_id) FROM etl_batch"; }
batch_status() { sql_value "SELECT status FROM etl_batch WHERE batch_id = $1"; }

# A fingerprint of the warehouse contents: if a rerun changes anything, this changes.
# MAX(load_batch_id) per table catches a rerun that needlessly REWRITES unchanged
# rows: every MERGE/UPDATE stamps the rows it touches with the current batch id.
snapshot() {
    sql_value "SELECT (SELECT COUNT(*) || '/' || TO_CHAR(SUM(price), 'fm99999999.00') || '/' || SUM(customer_key)
                       || '/' || SUM(NVL(delivered_date_key, 0)) || '/' || SUM(ORA_HASH(order_status))
                       || '/' || MAX(load_batch_id) FROM fact_sales)
               || '|' || (SELECT COUNT(*) || '/' || MAX(version) || '/' || MAX(load_batch_id) FROM dim_customer)
               || '|' || (SELECT COUNT(*) || '/' || MAX(load_batch_id) FROM dim_product)
               || '|' || (SELECT COUNT(*) || '/' || MAX(load_batch_id) FROM dim_seller)
               || '|' || (SELECT COUNT(*) || '/' || MAX(load_batch_id) FROM dim_payment_type) FROM dual"
}

# The order_id|order_item_id key of data line N of the raw order-items file.
item_key() {
    sed -n "$(( $1 + 1 ))p" data/raw/olist_order_items_dataset.csv | tr -d '"' | awk -F, '{ print $1 "|" $2 }'
}

started=$(date +%s)
echo "Warehouse test suite - $(date '+%Y-%m-%d %H:%M:%S')"

# -----------------------------------------------------------------------------
section "0. Preconditions"
check "raw Olist files present in data/raw" \
      "$(ls data/raw/olist_orders_dataset.csv data/raw/olist_order_items_dataset.csv data/raw/olist_customers_dataset.csv 2>/dev/null | wc -l)" "3"
check "no other load holds the lock" "$( [ -f logs/nightly.lock ] && echo held || echo free )" "free"

# -----------------------------------------------------------------------------
section "1. Schema: reset to an empty schema and install"
bin/install.sh --reset > /dev/null 2>&1
check "install.sh --reset exit code" "$?" "0"
check "fact tables (FACT_*)"                  "$(sql_value "SELECT COUNT(*) FROM user_tables WHERE table_name LIKE 'FACT\_%' ESCAPE '\'")" "1"
check "dimension tables (DIM_*)"              "$(sql_value "SELECT COUNT(*) FROM user_tables WHERE table_name LIKE 'DIM\_%' ESCAPE '\'")" "5"
check "fact + dimensions all have a primary key" \
      "$(sql_value "SELECT COUNT(*) FROM user_constraints WHERE constraint_type = 'P' AND (table_name LIKE 'DIM\_%' ESCAPE '\' OR table_name = 'FACT_SALES')")" "6"
check "fact foreign keys (3 date roles + 4 dimensions)" \
      "$(sql_value "SELECT COUNT(*) FROM user_constraints WHERE table_name = 'FACT_SALES' AND constraint_type = 'R'")" "7"
check "bitmap indexes on the fact"            "$(sql_value "SELECT COUNT(*) FROM user_indexes WHERE table_name = 'FACT_SALES' AND index_type = 'BITMAP'")" "4"
check "dim_date days (2016-01-01..2019-12-31)" "$(sql_value "SELECT COUNT(*) FROM dim_date")" "1461"
check "-1 Unknown row in each of 4 dimensions" \
      "$(sql_value "SELECT (SELECT COUNT(*) FROM dim_customer WHERE customer_key = -1) + (SELECT COUNT(*) FROM dim_product WHERE product_key = -1)
                          + (SELECT COUNT(*) FROM dim_seller WHERE seller_key = -1) + (SELECT COUNT(*) FROM dim_payment_type WHERE payment_type_key = -1) FROM dual")" "4"
check "sequences"                             "$(sql_value "SELECT COUNT(*) FROM user_sequences")" "6"
check "packages compiled VALID (5 specs + 5 bodies)" \
      "$(sql_value "SELECT COUNT(*) FROM user_objects WHERE object_type LIKE 'PACKAGE%' AND status = 'VALID'")" "10"
check "PL/SQL compilation errors"             "$(sql_value "SELECT COUNT(*) FROM user_errors")" "0"
check "report views (V_RPT_*)"                "$(sql_value "SELECT COUNT(*) FROM user_views WHERE view_name LIKE 'V\_RPT\_%' ESCAPE '\'")" "12"

# -----------------------------------------------------------------------------
section "2. First full load from data/raw"
rm -f logs/nightly.lock
check "nightly_load.sh exit code"             "$(load)" "0"
batch=$(last_batch)
check "batch status"                          "$(batch_status "$batch")" "SUCCESS"
check "fact_sales rows = order-items file"    "$(sql_value "SELECT COUNT(*) FROM fact_sales")" "112650"
check "sum(price) = CSV total"                "$(sql_value "SELECT TO_CHAR(SUM(price), 'fm99999999.00') FROM fact_sales")" "13591643.70"
check "current customers = distinct people"   "$(sql_value "SELECT COUNT(*) FROM dim_customer WHERE is_current = 'Y' AND customer_key <> -1")" "96096"
check "customer versions (all version 1)"     "$(sql_value "SELECT COUNT(*) || '/' || MAX(version) FROM dim_customer WHERE customer_key <> -1")" "96096/1"
check "products"                              "$(sql_value "SELECT COUNT(*) FROM dim_product WHERE product_key <> -1")" "32951"
check "sellers"                               "$(sql_value "SELECT COUNT(*) FROM dim_seller WHERE seller_key <> -1")" "3095"
check "payment types"                         "$(sql_value "SELECT COUNT(*) FROM dim_payment_type WHERE payment_type_key <> -1")" "5"
check "errors logged"                         "$(sql_value "SELECT COUNT(*) FROM etl_error_log WHERE batch_id = $batch")" "0"
check "bitmap indexes usable after the load"  "$(sql_value "SELECT COUNT(*) FROM user_indexes WHERE index_type = 'BITMAP' AND status = 'VALID'")" "4"

# -----------------------------------------------------------------------------
section "3. Second full load: idempotency, stale lock, log rotation (one run checks all three)"
before=$(snapshot)
echo 999999 > logs/nightly.lock                     # a lock left by a process that no longer exists
for i in $(seq -w 1 20); do                         # 20 old logs from "January"
    touch -d "2026-01-$i 02:00" "logs/nightly/nightly_202601${i}_020000.log"
done
check "nightly_load.sh exit code (despite stale lock)" "$(load)" "0"
after=$(snapshot)
check "warehouse unchanged by the rerun"      "$after" "$before"
check "stale lock detected and removed"       "$(grep -c 'Stale lock' "$(latest_log)")" "1"
check "lock file released after the run"      "$( [ -f logs/nightly.lock ] && echo present || echo absent )" "absent"
check "log rotation kept the newest 14 logs"  "$(ls logs/nightly/nightly_*.log | wc -l)" "14"
check "newest log is this run's, not a dummy" "$(grep -c 'SUCCESS: full load finished' "$(latest_log)")" "1"

# -----------------------------------------------------------------------------
section "4. Lock held by a running process"
sleep 300 &
live_pid=$!
echo "$live_pid" > logs/nightly.lock
batch_before=$(last_batch)
check "nightly_load.sh exit code (3 = skipped)" "$(load)" "3"
check "database not touched (no new batch)"   "$(last_batch)" "$batch_before"
check "other process's lock left in place"    "$(cat logs/nightly.lock)" "$live_pid"
kill "$live_pid"; wait "$live_pid" 2> /dev/null
rm -f logs/nightly.lock

# -----------------------------------------------------------------------------
section "5. Broken input file: row-level error logging"
# data/test = copy of the raw extract with 4 deliberate faults:
#   3 order lines with price 'abc'            -> rejected when converting (layer 1)
#   1 order delivered in 2031 (outside dim_date) -> rejected by the foreign key (layer 2)
mkdir -p data/test
rm -f data/test/*.csv
for f in olist_customers_dataset olist_order_payments_dataset olist_products_dataset \
         olist_sellers_dataset product_category_name_translation; do
    cp "data/raw/$f.csv" data/test/
done
awk -F, -v OFS=, 'NR == 101 || NR == 50001 || NR == 112001 { $6 = "abc" } { print }' \
    data/raw/olist_order_items_dataset.csv > data/test/olist_order_items_dataset.csv
one_item_order=$(tr -d '"' < data/raw/olist_order_items_dataset.csv \
    | awk -F, 'NR > 1 { n[$1]++ } END { for (o in n) if (n[o] == 1) print o }' | sort | head -1)
order_line=$(grep -n "$one_item_order" data/raw/olist_orders_dataset.csv | cut -d: -f1)
awk -F, -v OFS=, -v L="$order_line" 'NR == L { $7 = "2031-01-01 00:00:00" } { print }' \
    data/raw/olist_orders_dataset.csv > data/test/olist_orders_dataset.csv
expected_keys=$(printf '%s\n' "$(item_key 100)" "$(item_key 50000)" "$(item_key 112000)" "$one_item_order|1" | sort | paste -sd, -)

before=$(snapshot)
check "nightly_load.sh exit code (2 = rows rejected)" "$(load --source TEST_DIR)" "2"
batch=$(last_batch)
check "batch status"                          "$(batch_status "$batch")" "SUCCESS_WITH_ERRORS"
check "exactly the 4 bad rows logged, by key" \
      "$(sql_value "SELECT LISTAGG(source_key, ',') WITHIN GROUP (ORDER BY source_key) FROM etl_error_log WHERE batch_id = $batch")" "$expected_keys"
check "3 conversion errors (ORA-06502) + 1 foreign-key error (ORA-02291)" \
      "$(sql_value "SELECT SUM(CASE WHEN error_code = -6502 THEN 1 ELSE 0 END) || '+' || SUM(CASE WHEN error_code = -2291 THEN 1 ELSE 0 END) FROM etl_error_log WHERE batch_id = $batch")" "3+1"
check "all good rows kept, nothing else changed" "$(snapshot)" "$before"

# -----------------------------------------------------------------------------
section "6. Missing input file: step-level failure"
rm -f data/test/olist_customers_dataset.csv
check "nightly_load.sh exit code (1 = failed)" "$(load --source TEST_DIR)" "1"
batch=$(last_batch)
check "batch status"                          "$(batch_status "$batch")" "FAILED"
check "one error logged, naming the missing file (KUP-04040)" \
      "$(sql_value "SELECT COUNT(*) || '/' || SUM(CASE WHEN error_message LIKE '%KUP-04040%olist_customers_dataset.csv%' THEN 1 ELSE 0 END) FROM etl_error_log WHERE batch_id = $batch")" "1/1"
check "warehouse untouched by the failed load" "$(snapshot)" "$before"
rm -f data/test/*.csv
check "recovery: next normal load succeeds"   "$(load)" "0"

# -----------------------------------------------------------------------------
section "7. SCD Type 2: customer delta extract"
bin/make_delta.sh > /dev/null
check "make_delta.sh exit code"               "$?" "0"
delta_rows=$(( $(wc -l < data/delta/customer_delta.csv) - 1 ))
check "delta extract rows (real address changes)" "$delta_rows" "249"
check "nightly_load.sh --delta exit code"     "$(load --delta)" "0"
check "version-2 rows = delta rows"           "$(sql_value "SELECT COUNT(*) FROM dim_customer WHERE version = 2")" "$delta_rows"
check "closed rows = delta rows"              "$(sql_value "SELECT COUNT(*) FROM dim_customer WHERE is_current = 'N'")" "$delta_rows"
check "current customers still 96096"         "$(sql_value "SELECT COUNT(*) FROM dim_customer WHERE is_current = 'Y' AND customer_key <> -1")" "96096"
check "nobody has two current rows" \
      "$(sql_value "SELECT COUNT(*) FROM (SELECT customer_unique_id FROM dim_customer WHERE is_current = 'Y' GROUP BY customer_unique_id HAVING COUNT(*) > 1)")" "0"
check "old version ends exactly where new one starts" \
      "$(sql_value "SELECT COUNT(*) FROM dim_customer v1 JOIN dim_customer v2 ON v2.customer_unique_id = v1.customer_unique_id AND v2.version = v1.version + 1 WHERE v1.effective_to <> v2.effective_from")" "0"
check "current rows match the delta file" \
      "$(sql_value "SELECT COUNT(*) FROM ext_customer_delta x JOIN dim_customer d ON d.customer_unique_id = x.customer_unique_id AND d.is_current = 'Y'
                    WHERE DECODE(d.city, x.customer_city, 0, 1) = 1 OR DECODE(d.state, x.customer_state, 0, 1) = 1
                       OR DECODE(d.zip_code_prefix, LPAD(x.customer_zip_code_prefix, 5, '0'), 0, 1) = 1")" "0"
before=$(snapshot)
check "second --delta run exit code"          "$(load --delta)" "0"
check "second --delta run changed nothing"    "$(snapshot)" "$before"

# -----------------------------------------------------------------------------
section "8. Batch abandoned by a killed process"
bin/sql.sh -c "INSERT INTO etl_batch (batch_id, feed_name, source_dir, started_at, status)
VALUES (seq_etl_batch.NEXTVAL, 'FULL', 'RAW_DIR', SYSDATE - 1/24, 'RUNNING');
COMMIT;" > /dev/null
abandoned=$(sql_value "SELECT MAX(batch_id) FROM etl_batch WHERE status = 'RUNNING'")
check "next run exit code"                    "$(load --delta)" "0"
check "abandoned batch marked FAILED"         "$(batch_status "$abandoned")" "FAILED"
check "explanation logged for it"             "$(sql_value "SELECT COUNT(*) FROM etl_error_log WHERE batch_id = $abandoned")" "1"

# -----------------------------------------------------------------------------
section "9. Report views"
for view in $(bin/sql.sh -c "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT LOWER(view_name) FROM user_views WHERE view_name LIKE 'V\_RPT\_%' ESCAPE '\' ORDER BY 1;"); do
    rows=$(sql_value "SELECT COUNT(*) FROM $view")
    check "$view returns rows ($rows)" "$( [ "$rows" -gt 0 ] 2> /dev/null && echo yes || echo no )" "yes"
done
check "every view stores its business question" \
      "$(sql_value "SELECT COUNT(*) FROM user_tab_comments WHERE table_name LIKE 'V\_RPT\_%' ESCAPE '\' AND comments IS NOT NULL")" "12"

# -----------------------------------------------------------------------------
section "10. Command-line arguments"
check "unknown option rejected (exit 4)"      "$(load --bogus)" "4"
check "unsafe --source rejected (exit 4)"     "$(load --source 'x; rm -rf /')" "4"

# -----------------------------------------------------------------------------
section "11. Tableau exports"
bin/export_tableau.sh > /dev/null
check "export_tableau.sh exit code"           "$?" "0"
check "revenue_trend.csv header" "$(head -1 tableau/revenue_trend.csv)" \
      "month_start,year_num,month_num,order_count,revenue,avg_order_value,prev_month_revenue,mom_growth_pct,ytd_revenue"
check "revenue_trend.csv rows = view rows" \
      "$(( $(wc -l < tableau/revenue_trend.csv) - 1 ))" "$(sql_value "SELECT COUNT(*) FROM v_rpt_monthly_revenue")"
check "revenue_trend.csv revenue total = warehouse" \
      "$(awk -F, 'NR > 1 { s += $5 } END { printf "%.2f", s }' tableau/revenue_trend.csv)" \
      "$(sql_value "SELECT TO_CHAR(SUM(price), 'fm99999999.00') FROM fact_sales WHERE order_status NOT IN ('canceled', 'unavailable')")"
check "cohort_retention.csv header" "$(head -1 tableau/cohort_retention.csv)" \
      "cohort_month,months_since_first,cohort_size,active_customers,retention_pct"
check "cohort_retention.csv rows = view rows" \
      "$(( $(wc -l < tableau/cohort_retention.csv) - 1 ))" "$(sql_value "SELECT COUNT(*) FROM v_rpt_cohort_retention")"

# -----------------------------------------------------------------------------
section "12. Integration points for other projects"
# Read-only reporting user (created by docker/oracle/init/03_create_report_user.sh).
check "install granted SELECT on all 12 views to DW_REPORTING" \
      "$(sql_value "SELECT COUNT(*) FROM user_tab_privs_made WHERE grantee = 'DW_REPORTING' AND privilege = 'SELECT' AND table_name LIKE 'V\_RPT\_%' ESCAPE '\'")" "12"
check "reporting user can read a view" \
      "$(bin/sql.sh --report -c "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM dw.v_rpt_monthly_revenue;" | tr -d '[:space:]')" \
      "$(sql_value "SELECT COUNT(*) FROM v_rpt_monthly_revenue")"
check "reporting user sees only the 12 report views in DW" \
      "$(bin/sql.sh --report -c "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) || '/' || SUM(CASE WHEN object_name LIKE 'V\_RPT\_%' ESCAPE '\' THEN 1 ELSE 0 END) FROM all_objects WHERE owner = 'DW';" | tr -d '[:space:]')" "12/12"
check "reporting user cannot read the fact table" \
      "$(bin/sql.sh --report -c "SELECT COUNT(*) FROM dw.fact_sales;" 2>&1 | grep -o 'ORA-00942' | head -1)" "ORA-00942"
check "reporting user cannot change data" \
      "$(bin/sql.sh --report -c "DELETE FROM dw.v_rpt_monthly_revenue;" 2>&1 | grep -o 'ORA-01031' | head -1)" "ORA-01031"

# Pre-load check (PRELOAD_CHECK in .env, or --preload-check on the command line).
batch_before=$(last_batch)
check "failing pre-load check skips the load (exit 5)" "$(load --delta --preload-check 'exit 7')" "5"
check "database not touched when the check fails" "$(last_batch)" "$batch_before"
check "check output and reason are in the run log" \
      "$(grep -c -E 'Pre-load check: exit 7|pre-load check failed \(its exit code 7\)' "$(latest_log)")" "2"
check "passing check sees mode, directory and folder, then the load runs" \
      "$(load --delta --preload-check '[ "$LOAD_MODE" = delta ] && [ "$LOAD_SOURCE_DIR" = DELTA_DIR ] && [ -f "$LOAD_SOURCE_PATH/customer_delta.csv" ]')" "0"

# -----------------------------------------------------------------------------
echo
echo "=== RESULT: $PASSED passed, $FAILED failed  ($(( $(date +%s) - started )) s)"
[ "$FAILED" -eq 0 ]
