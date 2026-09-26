-- =============================================================================
-- v_rpt_monthly_revenue
-- Business question: How is revenue trending month by month, how does each
--                    month compare with the previous one, and what is the
--                    running total for the year?
-- SQL features:      CTEs, LAG() OVER, SUM() OVER (running total)
-- One row per:       calendar month from the first to the last order month.
-- Feeds:             Tableau dashboard 1 (tableau/revenue_trend.csv).
--
-- The month list comes from dim_date, not from the sales, so a month with no
-- sales still appears with 0. Otherwise LAG would compare a month with the
-- last month that HAD sales (e.g. Dec 2016 with Oct 2016) and call it "previous".
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_monthly_revenue AS
WITH sales_by_month AS (
    SELECT d.month_start_date           AS month_start,
           COUNT(DISTINCT f.order_id)   AS order_count,
           SUM(f.price)                 AS revenue
    FROM   fact_sales f
    JOIN   dim_date d ON d.date_key = f.order_date_key
    WHERE  f.order_status NOT IN ('canceled', 'unavailable')
    GROUP  BY d.month_start_date
),
all_months AS (
    SELECT DISTINCT d.month_start_date AS month_start, d.year_num, d.month_num
    FROM   dim_date d
    WHERE  d.month_start_date BETWEEN (SELECT MIN(month_start) FROM sales_by_month)
                                  AND (SELECT MAX(month_start) FROM sales_by_month)
),
monthly AS (
    SELECT m.month_start,
           m.year_num,
           m.month_num,
           NVL(s.order_count, 0) AS order_count,
           NVL(s.revenue, 0)     AS revenue
    FROM   all_months m
    LEFT JOIN sales_by_month s ON s.month_start = m.month_start
)
SELECT month_start,
       year_num,
       month_num,
       order_count,
       revenue,
       ROUND(revenue / NULLIF(order_count, 0), 2)                        AS avg_order_value,
       LAG(revenue) OVER (ORDER BY month_start)                          AS prev_month_revenue,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY month_start))
                 / NULLIF(LAG(revenue) OVER (ORDER BY month_start), 0), 1) AS mom_growth_pct,
       SUM(revenue) OVER (PARTITION BY year_num ORDER BY month_start)    AS ytd_revenue
FROM   monthly;

COMMENT ON TABLE v_rpt_monthly_revenue IS 'How is revenue trending month by month, how does each month compare with the previous one, and what is the running total for the year?';
