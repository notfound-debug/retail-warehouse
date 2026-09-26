-- =============================================================================
-- v_rpt_weekday_orders_pivot
-- Business question: Which weekday gets the most orders, and did that change
--                    between 2017 and 2018?
-- SQL features:      CTE, PIVOT
-- One row per:       weekday (Monday..Sunday); one order-count column per year.
--
-- The CTE reduces the fact (one row per order line) to one row per order, so
-- COUNT counts orders, not lines. PIVOT then turns the years into columns.
-- 2018 only runs to October, so compare the shape (which day is highest),
-- not the absolute totals.
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_weekday_orders_pivot AS
WITH orders_by_weekday AS (
    SELECT DISTINCT
           f.order_id,
           d.day_of_week_num,
           d.day_name,
           d.year_num
    FROM   fact_sales f
    JOIN   dim_date d ON d.date_key = f.order_date_key
    WHERE  f.order_status NOT IN ('canceled', 'unavailable')
    AND    d.year_num IN (2017, 2018)
)
SELECT *
FROM   orders_by_weekday
PIVOT (
    COUNT(order_id) FOR year_num IN (2017 AS orders_2017, 2018 AS orders_2018)
);

COMMENT ON TABLE v_rpt_weekday_orders_pivot IS 'Which weekday gets the most orders, and did that change between 2017 and 2018?';
