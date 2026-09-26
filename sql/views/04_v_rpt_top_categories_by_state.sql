-- =============================================================================
-- v_rpt_top_categories_by_state
-- Business question: What are the top 3 product categories by revenue in each
--                    customer state?
-- SQL features:      CTE, RANK() OVER (PARTITION BY ...)
-- One row per:       (customer state, category) for the top 3 of each state.
--
-- RANK restarts at 1 for every state (PARTITION BY state). With RANK, two
-- categories with exactly the same revenue share a rank, so a state can show
-- more than 3 rows on a tie; ROW_NUMBER would silently drop one of them.
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_top_categories_by_state AS
WITH revenue_by_state_category AS (
    SELECT c.state            AS customer_state,
           p.category_name_en AS category,
           SUM(f.price)       AS revenue,
           COUNT(DISTINCT f.order_id) AS order_count
    FROM   fact_sales f
    JOIN   dim_customer c ON c.customer_key = f.customer_key
    JOIN   dim_product  p ON p.product_key  = f.product_key
    WHERE  f.order_status NOT IN ('canceled', 'unavailable')
    GROUP  BY c.state, p.category_name_en
),
ranked AS (
    SELECT customer_state,
           category,
           revenue,
           order_count,
           RANK() OVER (PARTITION BY customer_state ORDER BY revenue DESC) AS category_rank
    FROM   revenue_by_state_category
)
SELECT customer_state, category_rank, category, revenue, order_count
FROM   ranked
WHERE  category_rank <= 3;

COMMENT ON TABLE v_rpt_top_categories_by_state IS 'What are the top 3 product categories by revenue in each customer state?';
