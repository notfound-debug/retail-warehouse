-- =============================================================================
-- revenue_trend.sql
-- Tableau data source for dashboard 1 (Revenue Trend): tableau/revenue_trend.csv
-- Source view: v_rpt_monthly_revenue (one row per month). Run via bin/export_tableau.sh.
--
-- Tableau Public cannot connect to Oracle, only to files, so the view is
-- exported to CSV. Dates are written as YYYY-MM-DD, which Tableau recognises
-- as dates. Decimals go through TO_CHAR so that values below 1 keep their
-- leading zero (sqlplus would otherwise print ".4"). No text column can
-- contain a comma, so values are written without quotes.
-- =============================================================================
SET FEEDBACK OFF VERIFY OFF TERMOUT OFF TRIMSPOOL ON PAGESIZE 50000
SET MARKUP CSV ON QUOTE OFF
SPOOL tableau/revenue_trend.csv

SELECT TO_CHAR(month_start, 'YYYY-MM-DD')             AS "month_start",
       year_num                                       AS "year_num",
       month_num                                      AS "month_num",
       order_count                                    AS "order_count",
       TO_CHAR(revenue, 'fm99999990.00')              AS "revenue",
       TO_CHAR(avg_order_value, 'fm99999990.00')      AS "avg_order_value",
       TO_CHAR(prev_month_revenue, 'fm99999990.00')   AS "prev_month_revenue",
       TO_CHAR(mom_growth_pct, 'fm99999990.0')        AS "mom_growth_pct",
       TO_CHAR(ytd_revenue, 'fm99999990.00')          AS "ytd_revenue"
FROM   v_rpt_monthly_revenue
ORDER  BY month_start;

SPOOL OFF
SET MARKUP CSV OFF
