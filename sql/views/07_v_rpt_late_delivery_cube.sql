-- =============================================================================
-- v_rpt_late_delivery_cube
-- Business question: What share of delivered orders arrived after the
--                    estimated delivery date, by customer state and year,
--                    with every subtotal?
-- SQL features:      CTE, CUBE, GROUPING_ID()
-- One row per:       (state, year), (state), (year) and () grand total.
--
-- Lateness is a property of an ORDER, not of an order line, so the CTE first
-- reduces the fact to one row per delivered order.
-- CUBE (state, year) produces every combination of subtotals, where ROLLUP
-- would only produce the hierarchy state -> (state, year):
--   grouping_level 0 = (state, year)   1 = state total
--                  2 = year total      3 = grand total
-- Date keys are YYYYMMDD numbers, so "delivered later than estimated" is a
-- plain numeric comparison.
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_late_delivery_cube AS
WITH delivered_orders AS (
    SELECT DISTINCT
           f.order_id,
           c.state   AS customer_state,
           d.year_num AS order_year,
           CASE WHEN f.delivered_date_key > f.estimated_delivery_date_key THEN 1 ELSE 0 END AS is_late
    FROM   fact_sales f
    JOIN   dim_customer c ON c.customer_key = f.customer_key
    JOIN   dim_date     d ON d.date_key     = f.order_date_key
    WHERE  f.order_status = 'delivered'
    AND    f.delivered_date_key IS NOT NULL
)
SELECT CASE WHEN GROUPING(customer_state) = 1 THEN 'ALL STATES' ELSE customer_state END AS customer_state,
       CASE WHEN GROUPING(order_year) = 1 THEN 'ALL YEARS' ELSE TO_CHAR(order_year) END  AS order_year,
       GROUPING_ID(customer_state, order_year)       AS grouping_level,
       COUNT(*)                                      AS delivered_orders,
       SUM(is_late)                                  AS late_orders,
       ROUND(100 * SUM(is_late) / COUNT(*), 2)       AS late_pct
FROM   delivered_orders
GROUP  BY CUBE (customer_state, order_year);

COMMENT ON TABLE v_rpt_late_delivery_cube IS 'What share of delivered orders arrived after the estimated delivery date, by customer state and year, with every subtotal?';
