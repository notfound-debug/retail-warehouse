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
