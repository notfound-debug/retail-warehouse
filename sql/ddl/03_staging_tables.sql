-- =============================================================================
-- 03_staging_tables.sql
-- Staging tables: a copy of the latest extract, one table per source file.
--
-- Why copy from the external tables at all? An external table re-reads the CSV
-- every time it is queried and cannot be indexed. Copying once gives every
-- later step a fast, consistent snapshot, and lets us re-run the dimension and
-- fact loads without touching the files again.
--
-- All columns are VARCHAR2 on purpose: staging accepts whatever the file
-- contains. Type conversion happens in pkg_dim / pkg_fact, where a bad value
-- can be logged against its business key instead of failing the file load.
-- pkg_stage TRUNCATEs and reloads these tables on every run.
-- =============================================================================

CREATE TABLE stg_customer (
    customer_id               VARCHAR2(50),
    customer_unique_id        VARCHAR2(50),
    customer_zip_code_prefix  VARCHAR2(20),
    customer_city             VARCHAR2(100),
    customer_state            VARCHAR2(20)
);

CREATE TABLE stg_order (
    order_id                       VARCHAR2(50),
    customer_id                    VARCHAR2(50),
    order_status                   VARCHAR2(30),
    order_purchase_timestamp       VARCHAR2(30),
    order_approved_at              VARCHAR2(30),
    order_delivered_carrier_date   VARCHAR2(30),
    order_delivered_customer_date  VARCHAR2(30),
    order_estimated_delivery_date  VARCHAR2(30)
);

CREATE TABLE stg_order_item (
    order_id             VARCHAR2(50),
    order_item_id        VARCHAR2(20),
    product_id           VARCHAR2(50),
    seller_id            VARCHAR2(50),
    shipping_limit_date  VARCHAR2(30),
    price                VARCHAR2(30),
    freight_value        VARCHAR2(30)
);

CREATE TABLE stg_payment (
    order_id              VARCHAR2(50),
    payment_sequential    VARCHAR2(20),
    payment_type          VARCHAR2(30),
    payment_installments  VARCHAR2(20),
    payment_value         VARCHAR2(30)
);

CREATE TABLE stg_product (
    product_id                  VARCHAR2(50),
    product_category_name       VARCHAR2(100),
    product_name_lenght         VARCHAR2(20),
    product_description_lenght  VARCHAR2(20),
    product_photos_qty          VARCHAR2(20),
    product_weight_g            VARCHAR2(20),
    product_length_cm           VARCHAR2(20),
    product_height_cm           VARCHAR2(20),
    product_width_cm            VARCHAR2(20)
);

CREATE TABLE stg_seller (
    seller_id               VARCHAR2(50),
    seller_zip_code_prefix  VARCHAR2(20),
    seller_city             VARCHAR2(100),
    seller_state            VARCHAR2(20)
);

CREATE TABLE stg_category_translation (
    product_category_name          VARCHAR2(100),
    product_category_name_english  VARCHAR2(100)
);

-- The loads join staging tables on these ids; without indexes each join would
-- scan the whole table. Rebuilt automatically when the tables are truncated.
CREATE INDEX ix_stg_order_id        ON stg_order (order_id);
CREATE INDEX ix_stg_order_item_id   ON stg_order_item (order_id);
CREATE INDEX ix_stg_payment_order   ON stg_payment (order_id);
CREATE INDEX ix_stg_customer_id     ON stg_customer (customer_id);

-- -----------------------------------------------------------------------------
-- v_stg_customer_source: one row per person (customer_unique_id), ready to be
-- compared with dim_customer by the SCD2 load.
--
-- The customers file has one row per ORDER, so a person with 3 orders has 3
-- rows, and 252 people have different addresses on different orders. Rule:
-- take the address on the person's EARLIEST order. The SCD2 delta extract
-- (data/delta) then carries the address from their latest order, so the
-- warehouse replays the real address changes found in the data.
--
-- How "earliest order" is picked: GROUP BY the person, and for each column
-- take MAX(col) KEEP (DENSE_RANK FIRST ORDER BY <earliest order first>).
-- Read it as: "sort this person's rows by purchase time, keep only the first
-- one, and return its value". (MAX only matters if two rows tie on the whole
-- ORDER BY, and customer_id as the last sort key rules that out.)
--
-- Why not the more familiar ROW_NUMBER() OVER (...) ... WHERE rn = 1? It gives
-- identical rows (checked with MINUS in M3), but when the SCD2 MERGE/INSERT
-- joined it to dim_customer, Oracle chose a "WINDOW SORT PUSHED RANK" plan that
-- burned ~8 s of CPU per statement; with KEEP each statement takes ~0.3 s.
--
-- Timestamps are text in 'YYYY-MM-DD HH24:MI:SS' format, which sorts in
-- date order as plain text, so no conversion is needed to order by them.
-- LEFT JOIN + NULLS LAST: a customer row with no staged order still counts.
-- customer_id is a tie-breaker so the choice is always the same (deterministic).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_stg_customer_source AS
SELECT c.customer_unique_id,
       MAX(LPAD(c.customer_zip_code_prefix, 5, '0'))
           KEEP (DENSE_RANK FIRST ORDER BY o.order_purchase_timestamp NULLS LAST, c.customer_id) AS zip_code_prefix,
       MAX(c.customer_city)
           KEEP (DENSE_RANK FIRST ORDER BY o.order_purchase_timestamp NULLS LAST, c.customer_id) AS city,
       MAX(c.customer_state)
           KEEP (DENSE_RANK FIRST ORDER BY o.order_purchase_timestamp NULLS LAST, c.customer_id) AS state
FROM stg_customer c
LEFT JOIN stg_order o ON o.customer_id = c.customer_id
GROUP BY c.customer_unique_id;
