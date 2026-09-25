-- =============================================================================
-- 02_external_tables.sql
-- External tables: each one is a read-only SQL view of a CSV file on the
-- database server. Nothing is copied until pkg_stage runs
--   INSERT INTO stg_x SELECT ... FROM ext_x.
--
-- Why external tables instead of SQL*Loader: the staging load becomes plain SQL
-- inside a PL/SQL package (same transaction handling, same error logging, same
-- batch id as every other step), and there are no control files or client-side
-- loader processes for the Bash wrapper to manage.
--
-- Common settings, explained once:
--   RECORDS DELIMITED BY NEWLINE   one line = one record (Unix LF line endings).
--                                The one exception is the category translation file,
--                                which has Windows line endings; see that table.
--   SKIP 1                       skip the header row.
--   OPTIONALLY ENCLOSED BY '"'   Olist quotes some fields and not others; two seller
--                                cities contain commas inside quotes.
--   MISSING FIELD VALUES ARE NULL  an empty trailing field becomes NULL instead of an error.
--   REJECT LIMIT 0               a structurally broken line fails the load loudly
--                                instead of being skipped silently into a .bad file.
-- Every column is VARCHAR2: the file is read as text, and conversion to
-- NUMBER/DATE happens later, where a failure can be logged with the row's key.
-- =============================================================================

CREATE TABLE ext_customers (
    customer_id               VARCHAR2(50),
    customer_unique_id        VARCHAR2(50),
    customer_zip_code_prefix  VARCHAR2(20),
    customer_city             VARCHAR2(100),
    customer_state            VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY raw_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE CHARACTERSET AL32UTF8
        SKIP 1
        BADFILE ext_log_dir:'ext_customers.bad'
        LOGFILE ext_log_dir:'ext_customers.log'
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('olist_customers_dataset.csv')
)
REJECT LIMIT 0;

-- Same layout as ext_customers, but reads the SCD2 delta extract (data/delta),
-- which bin/make_delta.sh generates.
CREATE TABLE ext_customer_delta (
    customer_id               VARCHAR2(50),
    customer_unique_id        VARCHAR2(50),
    customer_zip_code_prefix  VARCHAR2(20),
    customer_city             VARCHAR2(100),
    customer_state            VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY delta_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE CHARACTERSET AL32UTF8
        SKIP 1
        BADFILE ext_log_dir:'ext_customer_delta.bad'
        LOGFILE ext_log_dir:'ext_customer_delta.log'
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('customer_delta.csv')
)
REJECT LIMIT 0;

CREATE TABLE ext_orders (
    order_id                       VARCHAR2(50),
    customer_id                    VARCHAR2(50),
    order_status                   VARCHAR2(30),
    order_purchase_timestamp       VARCHAR2(30),
    order_approved_at              VARCHAR2(30),
    order_delivered_carrier_date   VARCHAR2(30),
    order_delivered_customer_date  VARCHAR2(30),
    order_estimated_delivery_date  VARCHAR2(30)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY raw_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE CHARACTERSET AL32UTF8
        SKIP 1
        BADFILE ext_log_dir:'ext_orders.bad'
        LOGFILE ext_log_dir:'ext_orders.log'
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('olist_orders_dataset.csv')
)
REJECT LIMIT 0;

CREATE TABLE ext_order_items (
    order_id             VARCHAR2(50),
    order_item_id        VARCHAR2(20),
    product_id           VARCHAR2(50),
    seller_id            VARCHAR2(50),
    shipping_limit_date  VARCHAR2(30),
    price                VARCHAR2(30),
    freight_value        VARCHAR2(30)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY raw_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE CHARACTERSET AL32UTF8
        SKIP 1
        BADFILE ext_log_dir:'ext_order_items.bad'
        LOGFILE ext_log_dir:'ext_order_items.log'
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('olist_order_items_dataset.csv')
)
REJECT LIMIT 0;

CREATE TABLE ext_payments (
    order_id              VARCHAR2(50),
    payment_sequential    VARCHAR2(20),
    payment_type          VARCHAR2(30),
    payment_installments  VARCHAR2(20),
    payment_value         VARCHAR2(30)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY raw_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE CHARACTERSET AL32UTF8
        SKIP 1
        BADFILE ext_log_dir:'ext_payments.bad'
        LOGFILE ext_log_dir:'ext_payments.log'
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('olist_order_payments_dataset.csv')
)
REJECT LIMIT 0;

-- Column names copy the source file exactly, including its spelling "lenght".
CREATE TABLE ext_products (
    product_id                  VARCHAR2(50),
    product_category_name       VARCHAR2(100),
    product_name_lenght         VARCHAR2(20),
    product_description_lenght  VARCHAR2(20),
    product_photos_qty          VARCHAR2(20),
    product_weight_g            VARCHAR2(20),
    product_length_cm           VARCHAR2(20),
    product_height_cm           VARCHAR2(20),
    product_width_cm            VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY raw_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE CHARACTERSET AL32UTF8
        SKIP 1
        BADFILE ext_log_dir:'ext_products.bad'
        LOGFILE ext_log_dir:'ext_products.log'
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('olist_products_dataset.csv')
)
REJECT LIMIT 0;

CREATE TABLE ext_sellers (
    seller_id               VARCHAR2(50),
    seller_zip_code_prefix  VARCHAR2(20),
    seller_city             VARCHAR2(100),
    seller_state            VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY raw_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE CHARACTERSET AL32UTF8
        SKIP 1
        BADFILE ext_log_dir:'ext_sellers.bad'
        LOGFILE ext_log_dir:'ext_sellers.log'
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('olist_sellers_dataset.csv')
)
REJECT LIMIT 0;

-- This file differs from the others in two ways:
--   * its header starts with a UTF-8 byte-order mark; SKIP 1 skips it along with the header;
--   * its lines end in carriage return + line feed (hex 0D 0A, Windows style).
--     Splitting on both bytes keeps a stray carriage return out of the English name.
--     (Hex is used because ORACLE_LOADER does not understand '\r\n'.)
CREATE TABLE ext_category_translation (
    product_category_name          VARCHAR2(100),
    product_category_name_english  VARCHAR2(100)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY raw_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY 0x'0D0A' CHARACTERSET AL32UTF8
        SKIP 1
        BADFILE ext_log_dir:'ext_category_translation.bad'
        LOGFILE ext_log_dir:'ext_category_translation.log'
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
        MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('product_category_name_translation.csv')
)
REJECT LIMIT 0;
