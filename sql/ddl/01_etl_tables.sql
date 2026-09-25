-- =============================================================================
-- 01_etl_tables.sql
-- ETL audit tables, written only by pkg_log.
--   etl_batch      one row per load run: when it ran, which feed, how it ended
--   etl_error_log  one row per error: which batch, which step, which source row
-- These are not part of the star schema; they record what the loads did.
-- =============================================================================

CREATE TABLE etl_batch (
    batch_id     NUMBER(10)     NOT NULL,
    feed_name    VARCHAR2(30)   NOT NULL,   -- FULL or CUSTOMER_DELTA
    source_dir   VARCHAR2(30),              -- Oracle directory object the files were read from
    started_at   DATE           NOT NULL,
    finished_at  DATE,
    status       VARCHAR2(20)   NOT NULL,
    error_count  NUMBER(10)     DEFAULT 0 NOT NULL,
    CONSTRAINT pk_etl_batch PRIMARY KEY (batch_id),
    CONSTRAINT ck_etl_batch_status
        CHECK (status IN ('RUNNING', 'SUCCESS', 'SUCCESS_WITH_ERRORS', 'FAILED'))
);

COMMENT ON TABLE etl_batch IS 'One row per ETL run (batch). Written by pkg_log.';

CREATE TABLE etl_error_log (
    error_id       NUMBER(12)      NOT NULL,
    batch_id       NUMBER(10)      NOT NULL,
    logged_at      DATE            DEFAULT SYSDATE NOT NULL,
    step_name      VARCHAR2(60)    NOT NULL,   -- e.g. PKG_FACT.LOAD_FACT_SALES
    source_key     VARCHAR2(200),              -- business key of the failed row, e.g. order_id|order_item_id
    error_code     NUMBER(10),                 -- Oracle error number, e.g. -1722
    error_message  VARCHAR2(4000),
    CONSTRAINT pk_etl_error_log PRIMARY KEY (error_id),
    CONSTRAINT fk_etl_error_batch FOREIGN KEY (batch_id) REFERENCES etl_batch (batch_id)
);

COMMENT ON TABLE etl_error_log IS 'One row per ETL error (row-level or step-level). Written by pkg_log.log_error in an autonomous transaction.';

CREATE INDEX ix_etl_error_batch ON etl_error_log (batch_id);
