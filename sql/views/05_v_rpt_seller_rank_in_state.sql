-- =============================================================================
-- v_rpt_seller_rank_in_state
-- Business question: Who are the 10 leading sellers in each seller state, and
--                    what share of that state's revenue does each one hold?
-- SQL features:      CTE, RANK() OVER, SUM() OVER (PARTITION BY ...) as a ratio
-- One row per:       seller, for the top 10 sellers of each state.
--
-- SUM(revenue) OVER (PARTITION BY seller_state) puts the state's total on
-- every seller row without a second GROUP BY query, so
-- share = seller revenue / state total. The share is computed before the
-- top-10 filter, so it is a share of the whole state, not of the top 10.
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_seller_rank_in_state AS
WITH seller_revenue AS (
    SELECT s.state                    AS seller_state,
           s.seller_id,
           s.city                     AS seller_city,
           SUM(f.price)               AS revenue,
           COUNT(DISTINCT f.order_id) AS order_count
    FROM   fact_sales f
    JOIN   dim_seller s ON s.seller_key = f.seller_key
    WHERE  f.order_status NOT IN ('canceled', 'unavailable')
    GROUP  BY s.state, s.seller_id, s.city
),
ranked AS (
    SELECT seller_state,
           seller_id,
           seller_city,
           revenue,
           order_count,
           RANK() OVER (PARTITION BY seller_state ORDER BY revenue DESC)              AS seller_rank,
           ROUND(100 * revenue / SUM(revenue) OVER (PARTITION BY seller_state), 2)    AS state_revenue_share_pct
    FROM   seller_revenue
)
SELECT seller_state, seller_rank, seller_id, seller_city, revenue, order_count, state_revenue_share_pct
FROM   ranked
WHERE  seller_rank <= 10;

COMMENT ON TABLE v_rpt_seller_rank_in_state IS 'Who are the 10 leading sellers in each seller state, and what share of that state''s revenue does each one hold?';
