-- =============================================================================
-- v_rpt_revenue_grouping_sets
-- Business question: What is revenue by year, by payment type, and in total,
--                    all in one result set?
-- SQL features:      GROUPING SETS, GROUPING_ID()
-- One row per:       year, plus one row per payment type, plus one total row.
--
-- GROUPING SETS lists exactly the groupings wanted, here three unrelated ones:
-- (year), (payment type) and () for the total. It is equivalent to three
-- GROUP BY queries joined with UNION ALL, but scans the fact only once.
-- ROLLUP and CUBE are shorthand for particular sets of GROUPING SETS.
--   breakdown = 'YEAR' / 'PAYMENT TYPE' / 'TOTAL' tells the rows apart.
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_revenue_grouping_sets AS
SELECT CASE GROUPING_ID(d.year_num, pt.payment_type_desc)
            WHEN 1 THEN 'YEAR'
            WHEN 2 THEN 'PAYMENT TYPE'
            WHEN 3 THEN 'TOTAL'
       END                                        AS breakdown,
       d.year_num,
       pt.payment_type_desc                       AS payment_type,
       COUNT(DISTINCT f.order_id)                 AS order_count,
       SUM(f.price)                               AS revenue
FROM   fact_sales f
JOIN   dim_date d          ON d.date_key = f.order_date_key
JOIN   dim_payment_type pt ON pt.payment_type_key = f.payment_type_key
WHERE  f.order_status NOT IN ('canceled', 'unavailable')
GROUP  BY GROUPING SETS ((d.year_num), (pt.payment_type_desc), ());

COMMENT ON TABLE v_rpt_revenue_grouping_sets IS 'What is revenue by year, by payment type, and in total, all in one result set?';
