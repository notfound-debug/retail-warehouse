-- =============================================================================
-- v_rpt_repeat_purchase_gap
-- Business question: For customers who ordered more than once, how many days
--                    pass between one order and the next?
-- SQL features:      CTEs, ROW_NUMBER(), LAG(), LEAD(), COUNT() OVER
-- One row per:       order of a repeat customer (a person with 2+ orders).
--
-- LAG looks at the previous row of the same person (ordered by date) and LEAD
-- at the next one, so each order sees both its neighbours without a self-join.
-- On the first order days_since_previous is NULL; on the last, next_order_date
-- is NULL.
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_repeat_purchase_gap AS
WITH customer_orders AS (
    -- One row per order (the fact has one row per order LINE).
    SELECT DISTINCT
           c.customer_unique_id,
           f.order_id,
           d.calendar_date AS order_date
    FROM   fact_sales f
    JOIN   dim_customer c ON c.customer_key = f.customer_key
    JOIN   dim_date     d ON d.date_key     = f.order_date_key
    WHERE  f.order_status NOT IN ('canceled', 'unavailable')
    AND    c.customer_key <> -1
),
sequenced AS (
    SELECT customer_unique_id,
           order_id,
           order_date,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_date, order_id) AS order_number,
           COUNT(*)     OVER (PARTITION BY customer_unique_id)                               AS total_orders,
           LAG(order_date)  OVER (PARTITION BY customer_unique_id ORDER BY order_date, order_id) AS previous_order_date,
           LEAD(order_date) OVER (PARTITION BY customer_unique_id ORDER BY order_date, order_id) AS next_order_date
    FROM   customer_orders
)
SELECT customer_unique_id,
       order_number,
       total_orders,
       order_id,
       order_date,
       previous_order_date,
       order_date - previous_order_date AS days_since_previous,
       next_order_date
FROM   sequenced
WHERE  total_orders > 1;

COMMENT ON TABLE v_rpt_repeat_purchase_gap IS 'For customers who ordered more than once, how many days pass between one order and the next?';
