-- =============================================================================
-- make_customer_delta.sql
-- Generates data/delta/customer_delta.csv, the SCD2 change feed.
-- Run through bin/make_delta.sh (after at least one full load from RAW_DIR).
--
-- Olist's customers file has one row per ORDER, so it already contains real
-- address changes: some people ordered from different addresses. The full
-- load puts each person's EARLIEST-order address into dim_customer (see
-- v_stg_customer_source). This script finds every person whose address on
-- their LATEST order differs, and writes that latest row exactly as it appears
-- in the raw file. Loading it (bin/nightly_load.sh --delta) therefore replays
-- real moves: no invented people, no invented values.
--
-- Deterministic: the output depends only on the raw files. The ORDER BY and
-- the customer_id tie-breakers give the same file byte for byte every time.
-- =============================================================================
-- A large PAGESIZE prints the header only once. (sqlplus CSV output still
-- begins with one empty line; bin/make_delta.sh removes it.)
SET FEEDBACK OFF VERIFY OFF TERMOUT OFF TRIMSPOOL ON NEWPAGE NONE PAGESIZE 50000

-- Staging must hold the real extract. If the latest full load read a test
-- folder, the staging tables contain deliberately broken data: stop.
DECLARE
    l_source_dir  etl_batch.source_dir%TYPE;
    l_status      etl_batch.status%TYPE;
BEGIN
    SELECT source_dir, status
    INTO   l_source_dir, l_status
    FROM   etl_batch
    WHERE  batch_id = (SELECT MAX(batch_id) FROM etl_batch WHERE feed_name = 'FULL');

    IF l_source_dir <> 'RAW_DIR' OR l_status <> 'SUCCESS' THEN
        RAISE_APPLICATION_ERROR(-20020, 'Latest full load was ' || l_source_dir || '/' || l_status
            || '; run bin/nightly_load.sh (a successful RAW_DIR load) first.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20021, 'No full load yet; run bin/nightly_load.sh first.');
END;
/

SET MARKUP CSV ON QUOTE ON
SPOOL data/delta/customer_delta.csv

WITH customer_orders AS (
    SELECT c.customer_id,
           c.customer_unique_id,
           c.customer_zip_code_prefix,
           c.customer_city,
           c.customer_state,
           ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                              ORDER BY o.order_purchase_timestamp, c.customer_id)           AS first_rank,
           ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                              ORDER BY o.order_purchase_timestamp DESC, c.customer_id DESC) AS latest_rank
    FROM   stg_customer c
    JOIN   stg_order o ON o.customer_id = c.customer_id
),
first_order AS (
    SELECT * FROM customer_orders WHERE first_rank = 1
),
latest_order AS (
    SELECT * FROM customer_orders WHERE latest_rank = 1
)
-- Quoted lower-case aliases so the header matches the raw file exactly.
SELECT l.customer_id              AS "customer_id",
       l.customer_unique_id       AS "customer_unique_id",
       l.customer_zip_code_prefix AS "customer_zip_code_prefix",
       l.customer_city            AS "customer_city",
       l.customer_state           AS "customer_state"
FROM   latest_order l
JOIN   first_order  f ON f.customer_unique_id = l.customer_unique_id
-- Same comparison the SCD2 load makes (zip padded to 5 digits, NULL-safe DECODE).
WHERE  DECODE(LPAD(l.customer_zip_code_prefix, 5, '0'), LPAD(f.customer_zip_code_prefix, 5, '0'), 0, 1) = 1
   OR  DECODE(l.customer_city,  f.customer_city,  0, 1) = 1
   OR  DECODE(l.customer_state, f.customer_state, 0, 1) = 1
ORDER  BY l.customer_unique_id;

SPOOL OFF
SET MARKUP CSV OFF
