-- =============================================================================
-- 05_dimensions.sql
-- The five dimension tables of the star schema.
--   dim_date          conformed, role-playing date dimension (generated, not loaded)
--   dim_customer      SCD Type 2: keeps a new row (version) each time an address changes
--   dim_product       Type 1: overwritten in place
--   dim_seller        Type 1
--   dim_payment_type  Type 1
--
-- Every dimension except dim_date gets a -1 "Unknown" row. If the fact load
-- cannot find a matching dimension row, it uses -1 instead of dropping the
-- sale or violating the foreign key.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- dim_date. One row per calendar day, 2016-01-01 to 2019-12-31. Populated by
-- 08_populate_dim_date.sql. Key = YYYYMMDD (e.g. 20170315): dates never change,
-- so a readable, sortable key is safe here (standard Kimball practice).
-- -----------------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key          NUMBER(8)     NOT NULL,
    calendar_date     DATE          NOT NULL,
    day_of_week_num   NUMBER(1)     NOT NULL,   -- ISO: Monday = 1 ... Sunday = 7
    day_name          VARCHAR2(9)   NOT NULL,
    day_of_month      NUMBER(2)     NOT NULL,
    iso_week_num      NUMBER(2)     NOT NULL,
    month_num         NUMBER(2)     NOT NULL,
    month_name        VARCHAR2(9)   NOT NULL,
    quarter_num       NUMBER(1)     NOT NULL,
    year_num          NUMBER(4)     NOT NULL,
    year_month        VARCHAR2(7)   NOT NULL,   -- '2017-03'
    month_start_date  DATE          NOT NULL,
    is_weekend        CHAR(1)       NOT NULL,
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key),
    CONSTRAINT uq_dim_date_calendar_date UNIQUE (calendar_date),
    CONSTRAINT ck_dim_date_is_weekend CHECK (is_weekend IN ('Y', 'N'))
);

COMMENT ON TABLE dim_date IS 'Conformed date dimension, one row per day. Plays three roles on fact_sales: order, delivered and estimated-delivery date.';

-- -----------------------------------------------------------------------------
-- dim_customer. SCD Type 2 on the customer's address.
-- Natural key = customer_unique_id (the person). Olist's customer_id is NOT
-- the person: it is generated per order.
-- A person has one row per address version:
--   effective_from / effective_to  half-open interval [from, to) when the version was current
--   is_current                     'Y' on exactly one row per person
--   version                        1, 2, 3 ... in the order the changes were loaded
-- -----------------------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_key        NUMBER(10)    NOT NULL,
    customer_unique_id  VARCHAR2(32)  NOT NULL,
    zip_code_prefix     VARCHAR2(5),
    city                VARCHAR2(60),
    state               VARCHAR2(2),
    effective_from      DATE          NOT NULL,
    effective_to        DATE          NOT NULL,
    is_current          CHAR(1)       NOT NULL,
    version             NUMBER(4)     NOT NULL,
    load_batch_id       NUMBER(10),
    CONSTRAINT pk_dim_customer PRIMARY KEY (customer_key),
    CONSTRAINT uq_dim_customer_version UNIQUE (customer_unique_id, version),
    CONSTRAINT ck_dim_customer_is_current CHECK (is_current IN ('Y', 'N')),
    CONSTRAINT ck_dim_customer_dates CHECK (effective_to >= effective_from)
);

-- At most one current row per person, guaranteed by the database itself.
-- The CASE expression is NULL for non-current rows, and NULLs are not stored in
-- a B-tree index, so only current rows take part in the uniqueness check.
CREATE UNIQUE INDEX uq_dim_customer_one_current
    ON dim_customer (CASE WHEN is_current = 'Y' THEN customer_unique_id END);

COMMENT ON TABLE dim_customer IS 'Customer dimension, SCD Type 2 on zip/city/state. Natural key customer_unique_id.';

INSERT INTO dim_customer (customer_key, customer_unique_id, zip_code_prefix, city, state,
                          effective_from, effective_to, is_current, version)
VALUES (-1, 'UNKNOWN', NULL, 'Unknown', NULL,
        DATE '1900-01-01', DATE '9999-12-31', 'Y', 1);

-- -----------------------------------------------------------------------------
-- dim_product. Type 1: if an attribute changes, the row is simply updated.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_product (
    product_key       NUMBER(10)     NOT NULL,
    product_id        VARCHAR2(32)   NOT NULL,
    category_name_pt  VARCHAR2(60)   NOT NULL,   -- original Portuguese category
    category_name_en  VARCHAR2(60)   NOT NULL,   -- English translation (falls back to Portuguese)
    weight_g          NUMBER(8),
    length_cm         NUMBER(6),
    height_cm         NUMBER(6),
    width_cm          NUMBER(6),
    photos_qty        NUMBER(3),
    load_batch_id     NUMBER(10),
    CONSTRAINT pk_dim_product PRIMARY KEY (product_key),
    CONSTRAINT uq_dim_product_id UNIQUE (product_id)
);

COMMENT ON TABLE dim_product IS 'Product dimension, Type 1. Natural key product_id.';

INSERT INTO dim_product (product_key, product_id, category_name_pt, category_name_en)
VALUES (-1, 'UNKNOWN', 'desconhecido', 'unknown');

-- -----------------------------------------------------------------------------
-- dim_seller. Type 1.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_seller (
    seller_key       NUMBER(10)    NOT NULL,
    seller_id        VARCHAR2(32)  NOT NULL,
    zip_code_prefix  VARCHAR2(5),
    city             VARCHAR2(60),
    state            VARCHAR2(2),
    load_batch_id    NUMBER(10),
    CONSTRAINT pk_dim_seller PRIMARY KEY (seller_key),
    CONSTRAINT uq_dim_seller_id UNIQUE (seller_id)
);

COMMENT ON TABLE dim_seller IS 'Seller dimension, Type 1. Natural key seller_id.';

INSERT INTO dim_seller (seller_key, seller_id, city)
VALUES (-1, 'UNKNOWN', 'Unknown');

-- -----------------------------------------------------------------------------
-- dim_payment_type. Type 1. Each order is assigned one "primary" payment type
-- (the method with the largest payment value); see pkg_fact.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_payment_type (
    payment_type_key   NUMBER(10)    NOT NULL,
    payment_type_code  VARCHAR2(20)  NOT NULL,
    payment_type_desc  VARCHAR2(40)  NOT NULL,
    load_batch_id      NUMBER(10),
    CONSTRAINT pk_dim_payment_type PRIMARY KEY (payment_type_key),
    CONSTRAINT uq_dim_payment_type_code UNIQUE (payment_type_code)
);

COMMENT ON TABLE dim_payment_type IS 'Payment method dimension, Type 1. Natural key payment_type_code.';

INSERT INTO dim_payment_type (payment_type_key, payment_type_code, payment_type_desc)
VALUES (-1, 'unknown', 'Unknown');

COMMIT;
