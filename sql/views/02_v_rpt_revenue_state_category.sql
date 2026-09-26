-- =============================================================================
-- v_rpt_revenue_state_category
-- Business question: Which customer states and product categories drive
--                    revenue, with a subtotal per state and a grand total?
-- SQL features:      ROLLUP, GROUPING(), GROUPING_ID()
-- One row per:       (state, category), plus one subtotal row per state and
--                    one grand-total row.
--
-- ROLLUP (state, category) produces three levels in one query:
--   (state, category)  detail                   grouping_level = 0
--   (state)            subtotal for the state   grouping_level = 1
--   ()                 grand total              grouping_level = 3
-- GROUPING(col) is 1 on the rows where that column was rolled up, which is how
-- a subtotal row is told apart from a genuine NULL value.
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_revenue_state_category AS
SELECT CASE WHEN GROUPING(c.state) = 1 THEN 'ALL STATES'
            ELSE c.state END                            AS customer_state,
       CASE WHEN GROUPING(p.category_name_en) = 1 THEN 'ALL CATEGORIES'
            ELSE p.category_name_en END                 AS category,
       GROUPING_ID(c.state, p.category_name_en)          AS grouping_level,
       COUNT(DISTINCT f.order_id)                        AS order_count,
       SUM(f.price)                                      AS revenue
FROM   fact_sales f
JOIN   dim_customer c ON c.customer_key = f.customer_key
JOIN   dim_product  p ON p.product_key  = f.product_key
WHERE  f.order_status NOT IN ('canceled', 'unavailable')
GROUP  BY ROLLUP (c.state, p.category_name_en);

COMMENT ON TABLE v_rpt_revenue_state_category IS 'Which customer states and product categories drive revenue, with a subtotal per state and a grand total?';
