-- =============================================================================
-- v_rpt_payment_mix_monthly
-- Business question: How does the share of revenue paid by credit card,
--                    boleto, voucher and debit card shift month by month?
-- SQL features:      CTE, PIVOT
-- One row per:       month with sales; one revenue column per payment type.
--
-- PIVOT turns rows into columns: the CTE has one row per (month, payment type),
-- and PIVOT spreads the payment types across as columns. PIVOT needs the list
-- of values written out, so the rare types (not_defined, unknown) are grouped
-- into 'other' first; that way the columns always add up to the total.
-- Payment type = the order's primary payment type (see pkg_fact).
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_payment_mix_monthly AS
WITH revenue_by_month_and_type AS (
    SELECT d.month_start_date AS month_start,
           CASE WHEN pt.payment_type_code IN ('credit_card', 'boleto', 'voucher', 'debit_card')
                THEN pt.payment_type_code
                ELSE 'other' END AS payment_type,
           f.price
    FROM   fact_sales f
    JOIN   dim_date d          ON d.date_key = f.order_date_key
    JOIN   dim_payment_type pt ON pt.payment_type_key = f.payment_type_key
    WHERE  f.order_status NOT IN ('canceled', 'unavailable')
),
pivoted AS (
    SELECT *
    FROM   revenue_by_month_and_type
    PIVOT (
        SUM(price) FOR payment_type IN (
            'credit_card' AS credit_card,
            'boleto'      AS boleto,
            'voucher'     AS voucher,
            'debit_card'  AS debit_card,
            'other'       AS other
        )
    )
)
SELECT month_start,
       NVL(credit_card, 0) AS credit_card_revenue,
       NVL(boleto, 0)      AS boleto_revenue,
       NVL(voucher, 0)     AS voucher_revenue,
       NVL(debit_card, 0)  AS debit_card_revenue,
       NVL(other, 0)       AS other_revenue,
       NVL(credit_card, 0) + NVL(boleto, 0) + NVL(voucher, 0) + NVL(debit_card, 0) + NVL(other, 0)
                           AS total_revenue,
       ROUND(100 * NVL(credit_card, 0)
             / (NVL(credit_card, 0) + NVL(boleto, 0) + NVL(voucher, 0) + NVL(debit_card, 0) + NVL(other, 0)), 1)
                           AS credit_card_share_pct,
       ROUND(100 * NVL(boleto, 0)
             / (NVL(credit_card, 0) + NVL(boleto, 0) + NVL(voucher, 0) + NVL(debit_card, 0) + NVL(other, 0)), 1)
                           AS boleto_share_pct
FROM   pivoted;

COMMENT ON TABLE v_rpt_payment_mix_monthly IS 'How does the share of revenue paid by credit card, boleto, voucher and debit card shift month by month?';
