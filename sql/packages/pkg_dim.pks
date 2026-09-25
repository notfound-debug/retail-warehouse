CREATE OR REPLACE PACKAGE pkg_dim AS
/*
    pkg_dim: loads the dimension tables from staging.

    What it does
      dim_payment_type, dim_product, dim_seller (Type 1)
          One set-based MERGE each, matched on the natural key: insert new
          members, update changed ones in place, leave unchanged rows alone.
      dim_customer (SCD Type 2)
          Step 1 MERGE (matched on customer_key): close the current row of
                 every person whose address (zip, city or state) differs from staging.
          Step 2 INSERT: add a new current version for every person who has
                 no current row (new people, and the ones just closed).
          Both steps commit together, so nobody is ever left without a current row.

    Why it exists
      The fact load needs every dimension row to exist first so it can look up
      surrogate keys. Keeping all dimension logic in one package makes the
      load order explicit and each dimension's change rules easy to find.

    Idempotent: running any procedure twice on the same staging data changes
    nothing the second time.
*/

    PROCEDURE load_payment_type (p_batch_id IN NUMBER);

    PROCEDURE load_product (p_batch_id IN NUMBER);

    PROCEDURE load_seller (p_batch_id IN NUMBER);

    -- p_batch_start becomes effective_to of closed rows and effective_from of
    -- new versions, so the old and new versions meet exactly (no gap, no overlap).
    PROCEDURE load_customer_scd2 (
        p_batch_id     IN NUMBER,
        p_batch_start  IN DATE
    );

END pkg_dim;
/
