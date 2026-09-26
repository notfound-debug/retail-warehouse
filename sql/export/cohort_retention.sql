-- =============================================================================
-- cohort_retention.sql
-- Tableau data source for dashboard 2 (Customer Cohort Retention):
-- tableau/cohort_retention.csv
-- Source view: v_rpt_cohort_retention (one row per cohort month x months since
-- first purchase, zero months included). Run via bin/export_tableau.sh.
-- Same CSV conventions as revenue_trend.sql.
-- =============================================================================
SET FEEDBACK OFF VERIFY OFF TERMOUT OFF TRIMSPOOL ON PAGESIZE 50000
SET MARKUP CSV ON QUOTE OFF
SPOOL tableau/cohort_retention.csv

SELECT TO_CHAR(cohort_month, 'YYYY-MM-DD')   AS "cohort_month",
       months_since_first                   AS "months_since_first",
       cohort_size                          AS "cohort_size",
       active_customers                     AS "active_customers",
       TO_CHAR(retention_pct, 'fm990.00')   AS "retention_pct"
FROM   v_rpt_cohort_retention
ORDER  BY cohort_month, months_since_first;

SPOOL OFF
SET MARKUP CSV OFF
