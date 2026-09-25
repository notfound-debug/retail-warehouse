-- =============================================================================
-- 07_indexes.sql
-- Indexes on the fact table's foreign keys.
--
-- BITMAP indexes on the LOW-cardinality foreign keys (few distinct values
-- compared with 112K rows):
--   order_date_key    634 distinct days
--   payment_type_key  6 values
--   seller_key        ~3,100 sellers
--   order_status      8 values
-- Why bitmap: a bitmap index stores one bit-string per distinct value, so for
-- columns like these it is far smaller than a B-tree, and Oracle can AND/OR
-- several bitmaps together to answer typical star-schema filters ("2017, paid by
-- boleto, delivered") before touching the table.
-- Their weakness is locking: one bitmap entry covers many rows, so concurrent
-- inserts/updates from many sessions block each other. That is why bitmap
-- indexes suit a warehouse (one nightly batch writer, many readers) and are
-- avoided in OLTP systems.
--
-- B-TREE indexes on the HIGH-cardinality foreign keys:
--   customer_key  ~96K distinct values, almost one per row
--   product_key   ~33K distinct values
-- A bitmap would hold almost one bit-string per row here, so it has no size
-- advantage over a normal B-tree.
-- =============================================================================

CREATE BITMAP INDEX bix_fact_order_date   ON fact_sales (order_date_key);
CREATE BITMAP INDEX bix_fact_payment_type ON fact_sales (payment_type_key);
CREATE BITMAP INDEX bix_fact_seller       ON fact_sales (seller_key);
CREATE BITMAP INDEX bix_fact_order_status ON fact_sales (order_status);

CREATE INDEX ix_fact_customer ON fact_sales (customer_key);
CREATE INDEX ix_fact_product  ON fact_sales (product_key);
