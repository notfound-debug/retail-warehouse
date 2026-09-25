-- =============================================================================
-- 06_fact.sql
-- fact_sales. Grain: one row per line item of each order
-- (one row of olist_order_items_dataset.csv).
--
-- order_id + order_item_id are "degenerate dimensions": identifiers that live on
-- the fact because there is nothing else to describe them. Together they are the
-- natural primary key, which also makes a duplicate load impossible.
-- There is no fact surrogate key: nothing references a fact row.
-- =============================================================================

CREATE TABLE fact_sales (
    order_id                     VARCHAR2(32)   NOT NULL,
    order_item_id                NUMBER(3)      NOT NULL,
    order_date_key               NUMBER(8)      NOT NULL,
    delivered_date_key           NUMBER(8),               -- NULL = not delivered (yet)
    estimated_delivery_date_key  NUMBER(8),
    customer_key                 NUMBER(10)     NOT NULL,
    product_key                  NUMBER(10)     NOT NULL,
    seller_key                   NUMBER(10)     NOT NULL,
    payment_type_key             NUMBER(10)     NOT NULL,
    order_status                 VARCHAR2(20)   NOT NULL,
    price                        NUMBER(10,2)   NOT NULL,
    freight_value                NUMBER(10,2)   NOT NULL,
    load_batch_id                NUMBER(10),
    CONSTRAINT pk_fact_sales PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_fact_order_date     FOREIGN KEY (order_date_key)              REFERENCES dim_date (date_key),
    CONSTRAINT fk_fact_delivered_date FOREIGN KEY (delivered_date_key)          REFERENCES dim_date (date_key),
    CONSTRAINT fk_fact_estimated_date FOREIGN KEY (estimated_delivery_date_key) REFERENCES dim_date (date_key),
    CONSTRAINT fk_fact_customer       FOREIGN KEY (customer_key)                REFERENCES dim_customer (customer_key),
    CONSTRAINT fk_fact_product        FOREIGN KEY (product_key)                 REFERENCES dim_product (product_key),
    CONSTRAINT fk_fact_seller         FOREIGN KEY (seller_key)                  REFERENCES dim_seller (seller_key),
    CONSTRAINT fk_fact_payment_type   FOREIGN KEY (payment_type_key)            REFERENCES dim_payment_type (payment_type_key),
    CONSTRAINT ck_fact_amounts CHECK (price >= 0 AND freight_value >= 0)
);

COMMENT ON TABLE fact_sales IS 'Sales fact. Grain: one row per order line item. Measures: price, freight_value.';
