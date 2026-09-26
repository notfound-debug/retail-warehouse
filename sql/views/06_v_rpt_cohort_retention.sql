-- =============================================================================
-- v_rpt_cohort_retention
-- Business question: Of the customers who first bought in month X, what
--                    percentage bought again 1, 2, 3 ... months later?
-- SQL features:      CTEs, MIN() OVER (PARTITION BY ...), CONNECT BY row generator
-- One row per:       (cohort month, months since first purchase) for every
--                    month up to the end of the data, including months where
--                    nobody came back (0%).
-- Feeds:             Tableau dashboard 2 (tableau/cohort_retention.csv).
--
-- A customer is the PERSON (customer_unique_id), not one SCD2 version, so a
-- customer who moved address still counts as one returning customer.
-- Cohort = the month of the person's first order.
-- The grid step fills in zero months: without it a month where nobody came
-- back would be missing instead of showing 0%, and an average retention
-- curve would be too high.
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_cohort_retention AS
WITH customer_months AS (
    -- One row per person per month in which they ordered.
    SELECT DISTINCT c.customer_unique_id, d.month_start_date AS order_month
    FROM   fact_sales f
    JOIN   dim_customer c ON c.customer_key = f.customer_key
    JOIN   dim_date     d ON d.date_key     = f.order_date_key
    WHERE  f.order_status NOT IN ('canceled', 'unavailable')
    AND    c.customer_key <> -1
),
with_cohort AS (
    -- MIN() OVER puts each person's first order month on every one of their rows.
    SELECT customer_unique_id,
           order_month,
           MIN(order_month) OVER (PARTITION BY customer_unique_id) AS cohort_month
    FROM   customer_months
),
activity AS (
    SELECT cohort_month,
           MONTHS_BETWEEN(order_month, cohort_month) AS months_since_first,
           COUNT(*)                                  AS active_customers
    FROM   with_cohort
    GROUP  BY cohort_month, MONTHS_BETWEEN(order_month, cohort_month)
),
cohorts AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM   with_cohort
    GROUP  BY cohort_month
),
grid AS (
    -- Every cohort x every month offset that falls inside the data.
    -- CONNECT BY LEVEL <= 36 generates offsets 0..35; the data spans 26 months.
    SELECT c.cohort_month, c.cohort_size, n.months_since_first
    FROM   cohorts c
    JOIN  (SELECT LEVEL - 1 AS months_since_first FROM dual CONNECT BY LEVEL <= 36) n
      ON   ADD_MONTHS(c.cohort_month, n.months_since_first)
               <= (SELECT MAX(order_month) FROM customer_months)
)
SELECT g.cohort_month,
       g.months_since_first,
       g.cohort_size,
       NVL(a.active_customers, 0)                                AS active_customers,
       ROUND(100 * NVL(a.active_customers, 0) / g.cohort_size, 2) AS retention_pct
FROM   grid g
LEFT JOIN activity a
       ON a.cohort_month = g.cohort_month
      AND a.months_since_first = g.months_since_first;

COMMENT ON TABLE v_rpt_cohort_retention IS 'Of the customers who first bought in month X, what percentage bought again 1, 2, 3 ... months later?';
