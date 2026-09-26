-- =============================================================================
-- v_rpt_category_quarter_pivot
-- Business question: How does each product category's revenue compare across
--                    the quarters of 2017 and 2018?
-- SQL features:      CTE, PIVOT
-- One row per:       product category; one revenue column per quarter.
--
-- Q4 2018 is almost empty: the dataset ends in October 2018. It is kept so
-- the columns are the full two years, and the value shows the data's end.
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_category_quarter_pivot AS
WITH category_quarter AS (
    SELECT p.category_name_en                      AS category,
           d.year_num || '_Q' || d.quarter_num     AS year_quarter,
           f.price
    FROM   fact_sales f
    JOIN   dim_product p ON p.product_key = f.product_key
    JOIN   dim_date    d ON d.date_key    = f.order_date_key
    WHERE  f.order_status NOT IN ('canceled', 'unavailable')
    AND    d.year_num IN (2017, 2018)
)
SELECT *
FROM   category_quarter
PIVOT (
    SUM(price) FOR year_quarter IN (
        '2017_Q1' AS rev_2017_q1,
        '2017_Q2' AS rev_2017_q2,
        '2017_Q3' AS rev_2017_q3,
        '2017_Q4' AS rev_2017_q4,
        '2018_Q1' AS rev_2018_q1,
        '2018_Q2' AS rev_2018_q2,
        '2018_Q3' AS rev_2018_q3,
        '2018_Q4' AS rev_2018_q4
    )
);

COMMENT ON TABLE v_rpt_category_quarter_pivot IS 'How does each product category''s revenue compare across the quarters of 2017 and 2018?';
