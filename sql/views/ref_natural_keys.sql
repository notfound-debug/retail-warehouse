-- =============================================================================
-- v_ref_natural_keys
-- Purpose:      the natural keys already in the warehouse, for applications that
--               check an incoming extract before it is loaded (referential
--               integrity), e.g. "does every seller_id in the new order-items
--               file exist?". It is reference data for such checks, not a report.
-- One row per:  (key_type, key_value), key_type = 'seller' | 'product' | 'customer'.
--
-- Keys only: no names, cities or other attributes, so the read-only reporting
-- user can run these checks without being able to read the dimension tables.
-- The -1 "Unknown" rows are excluded. A customer can have several SCD2
-- versions, so customers are DISTINCT: one row per person.
-- =============================================================================
CREATE OR REPLACE VIEW v_ref_natural_keys AS
SELECT 'seller'  AS key_type, seller_id  AS key_value FROM dim_seller  WHERE seller_key  <> -1
UNION ALL
SELECT 'product' AS key_type, product_id AS key_value FROM dim_product WHERE product_key <> -1
UNION ALL
SELECT DISTINCT 'customer' AS key_type, customer_unique_id AS key_value FROM dim_customer WHERE customer_key <> -1;

COMMENT ON TABLE v_ref_natural_keys IS 'Natural keys known to the warehouse (seller, product, customer), for pre-load referential-integrity checks. Keys only.';
