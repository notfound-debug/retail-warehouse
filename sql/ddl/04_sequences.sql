-- =============================================================================
-- 04_sequences.sql
-- Surrogate keys come from sequences (not IDENTITY columns) because:
--   * seq.NEXTVAL can be used directly inside MERGE ... WHEN NOT MATCHED THEN INSERT;
--   * we insert a fixed -1 "Unknown" row into each dimension, which a
--     GENERATED ALWAYS identity column would refuse.
-- CACHE 100: Oracle hands out numbers from memory in blocks of 100, which is
-- faster. The side effect is gaps in the numbers after a restart. Gaps do not
-- matter: a surrogate key has no meaning except "unique".
-- dim_date has no sequence: its key is the date itself as YYYYMMDD.
-- =============================================================================

CREATE SEQUENCE seq_dim_customer      START WITH 1 CACHE 100;
CREATE SEQUENCE seq_dim_product       START WITH 1 CACHE 100;
CREATE SEQUENCE seq_dim_seller        START WITH 1 CACHE 100;
CREATE SEQUENCE seq_dim_payment_type  START WITH 1 CACHE 100;

CREATE SEQUENCE seq_etl_batch         START WITH 1 CACHE 20;
CREATE SEQUENCE seq_etl_error         START WITH 1 CACHE 100;
