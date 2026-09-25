CREATE OR REPLACE PACKAGE BODY pkg_dim AS

    -- Shared error handler: log (autonomous), undo this step's changes, re-raise.
    PROCEDURE fail (p_batch_id IN NUMBER, p_step_name IN VARCHAR2)
    IS
    BEGIN
        pkg_log.log_error(p_batch_id, p_step_name, NULL, SQLCODE,
                          DBMS_UTILITY.FORMAT_ERROR_STACK || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
        ROLLBACK;
    END fail;

    -- Note on seq.NEXTVAL inside MERGE: Oracle evaluates it for every source
    -- row, matched or not, so matched rows "use up" sequence numbers. That only
    -- leaves gaps in the keys, which is harmless for a surrogate key.

    -- -------------------------------------------------------------------------
    PROCEDURE load_payment_type (p_batch_id IN NUMBER)
    IS
    BEGIN
        MERGE INTO dim_payment_type d
        USING (
            SELECT code,
                   CASE code
                       WHEN 'credit_card' THEN 'Credit card'
                       WHEN 'debit_card'  THEN 'Debit card'
                       WHEN 'boleto'      THEN 'Boleto (bank slip)'
                       WHEN 'voucher'     THEN 'Voucher'
                       WHEN 'not_defined' THEN 'Not defined'
                       ELSE INITCAP(REPLACE(code, '_', ' '))
                   END AS description
            FROM (SELECT DISTINCT payment_type AS code
                  FROM stg_payment
                  WHERE payment_type IS NOT NULL)
        ) s
        ON (d.payment_type_code = s.code)
        WHEN MATCHED THEN UPDATE
            SET d.payment_type_desc = s.description,
                d.load_batch_id     = p_batch_id
            WHERE d.payment_type_desc <> s.description
        WHEN NOT MATCHED THEN INSERT (payment_type_key, payment_type_code, payment_type_desc, load_batch_id)
            VALUES (seq_dim_payment_type.NEXTVAL, s.code, s.description, p_batch_id);

        pkg_log.info(RPAD('DIM_PAYMENT_TYPE', 26) || LPAD(SQL%ROWCOUNT, 9) || ' rows inserted/updated');
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            fail(p_batch_id, 'PKG_DIM.LOAD_PAYMENT_TYPE');
            RAISE;
    END load_payment_type;


    -- -------------------------------------------------------------------------
    -- Category: Portuguese name, or 'sem_categoria' ("no category") when blank.
    -- English name from the translation file; two categories have no
    -- translation, so fall back to the Portuguese name.
    -- DECODE(a, b, 0, 1) = 1 means "a differs from b", treating NULL = NULL as
    -- equal (a plain a <> b is never true when either side is NULL).
    -- -------------------------------------------------------------------------
    PROCEDURE load_product (p_batch_id IN NUMBER)
    IS
    BEGIN
        MERGE INTO dim_product d
        USING (
            SELECT p.product_id,
                   NVL(p.product_category_name, 'sem_categoria')                          AS category_name_pt,
                   COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category_name_en,
                   TO_NUMBER(p.product_weight_g)    AS weight_g,
                   TO_NUMBER(p.product_length_cm)   AS length_cm,
                   TO_NUMBER(p.product_height_cm)   AS height_cm,
                   TO_NUMBER(p.product_width_cm)    AS width_cm,
                   TO_NUMBER(p.product_photos_qty)  AS photos_qty
            FROM stg_product p
            LEFT JOIN stg_category_translation t
                   ON t.product_category_name = p.product_category_name
        ) s
        ON (d.product_id = s.product_id)
        WHEN MATCHED THEN UPDATE
            SET d.category_name_pt = s.category_name_pt,
                d.category_name_en = s.category_name_en,
                d.weight_g         = s.weight_g,
                d.length_cm        = s.length_cm,
                d.height_cm        = s.height_cm,
                d.width_cm         = s.width_cm,
                d.photos_qty       = s.photos_qty,
                d.load_batch_id    = p_batch_id
            WHERE DECODE(d.category_name_pt, s.category_name_pt, 0, 1) = 1
               OR DECODE(d.category_name_en, s.category_name_en, 0, 1) = 1
               OR DECODE(d.weight_g,   s.weight_g,   0, 1) = 1
               OR DECODE(d.length_cm,  s.length_cm,  0, 1) = 1
               OR DECODE(d.height_cm,  s.height_cm,  0, 1) = 1
               OR DECODE(d.width_cm,   s.width_cm,   0, 1) = 1
               OR DECODE(d.photos_qty, s.photos_qty, 0, 1) = 1
        WHEN NOT MATCHED THEN INSERT (product_key, product_id, category_name_pt, category_name_en,
                                      weight_g, length_cm, height_cm, width_cm, photos_qty, load_batch_id)
            VALUES (seq_dim_product.NEXTVAL, s.product_id, s.category_name_pt, s.category_name_en,
                    s.weight_g, s.length_cm, s.height_cm, s.width_cm, s.photos_qty, p_batch_id);

        pkg_log.info(RPAD('DIM_PRODUCT', 26) || LPAD(SQL%ROWCOUNT, 9) || ' rows inserted/updated');
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            fail(p_batch_id, 'PKG_DIM.LOAD_PRODUCT');
            RAISE;
    END load_product;


    -- -------------------------------------------------------------------------
    PROCEDURE load_seller (p_batch_id IN NUMBER)
    IS
    BEGIN
        MERGE INTO dim_seller d
        USING (
            SELECT seller_id,
                   LPAD(seller_zip_code_prefix, 5, '0') AS zip_code_prefix,
                   seller_city                          AS city,
                   seller_state                         AS state
            FROM stg_seller
        ) s
        ON (d.seller_id = s.seller_id)
        WHEN MATCHED THEN UPDATE
            SET d.zip_code_prefix = s.zip_code_prefix,
                d.city            = s.city,
                d.state           = s.state,
                d.load_batch_id   = p_batch_id
            WHERE DECODE(d.zip_code_prefix, s.zip_code_prefix, 0, 1) = 1
               OR DECODE(d.city,  s.city,  0, 1) = 1
               OR DECODE(d.state, s.state, 0, 1) = 1
        WHEN NOT MATCHED THEN INSERT (seller_key, seller_id, zip_code_prefix, city, state, load_batch_id)
            VALUES (seq_dim_seller.NEXTVAL, s.seller_id, s.zip_code_prefix, s.city, s.state, p_batch_id);

        pkg_log.info(RPAD('DIM_SELLER', 26) || LPAD(SQL%ROWCOUNT, 9) || ' rows inserted/updated');
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            fail(p_batch_id, 'PKG_DIM.LOAD_SELLER');
            RAISE;
    END load_seller;


    -- -------------------------------------------------------------------------
    -- SCD Type 2. Source: v_stg_customer_source (one row per person).
    --
    -- Step 1 is a MERGE matched on customer_key, not on is_current. MERGE
    -- forbids updating a column used in its ON clause (ORA-38104), and this
    -- step sets is_current to 'N'. So the USING query first finds the keys of
    -- the current rows whose address changed (one join), and the MERGE then
    -- closes exactly those rows by key.
    -- (A first version used UPDATE ... WHERE EXISTS (correlated subquery). Once
    -- statistics existed, Oracle ran the subquery once per dimension row,
    -- 96K times, and the step took over 10 minutes. The join form is one pass.)
    -- -------------------------------------------------------------------------
    PROCEDURE load_customer_scd2 (
        p_batch_id     IN NUMBER,
        p_batch_start  IN DATE
    )
    IS
        l_closed    NUMBER;
        l_inserted  NUMBER;
    BEGIN
        -- Step 1: close the current version of every person whose address changed.
        MERGE INTO dim_customer d
        USING (
            SELECT cur.customer_key
            FROM   dim_customer cur
            JOIN   v_stg_customer_source s
                   ON s.customer_unique_id = cur.customer_unique_id
            WHERE  cur.is_current = 'Y'
            AND   (   DECODE(cur.zip_code_prefix, s.zip_code_prefix, 0, 1) = 1
                   OR DECODE(cur.city,  s.city,  0, 1) = 1
                   OR DECODE(cur.state, s.state, 0, 1) = 1)
        ) changed
        ON (d.customer_key = changed.customer_key)
        WHEN MATCHED THEN UPDATE
            SET d.is_current    = 'N',
                d.effective_to  = p_batch_start,
                d.load_batch_id = p_batch_id;
        l_closed := SQL%ROWCOUNT;

        -- Step 2: insert a new current version for everyone without a current row:
        -- brand-new people (version 1) and people closed in step 1 (previous version + 1).
        -- "existing" summarises each person already in the dimension in one pass:
        -- their highest version, and whether they still have a current row.
        INSERT INTO dim_customer (customer_key, customer_unique_id, zip_code_prefix, city, state,
                                  effective_from, effective_to, is_current, version, load_batch_id)
        SELECT seq_dim_customer.NEXTVAL,
               s.customer_unique_id,
               s.zip_code_prefix,
               s.city,
               s.state,
               p_batch_start,
               DATE '9999-12-31',
               'Y',
               NVL(existing.max_version, 0) + 1,
               p_batch_id
        FROM   v_stg_customer_source s
        LEFT JOIN (
                   SELECT customer_unique_id,
                          MAX(version)                                    AS max_version,
                          MAX(CASE WHEN is_current = 'Y' THEN 1 ELSE 0 END) AS has_current
                   FROM   dim_customer
                   GROUP  BY customer_unique_id
               ) existing
               ON existing.customer_unique_id = s.customer_unique_id
        WHERE  NVL(existing.has_current, 0) = 0;
        l_inserted := SQL%ROWCOUNT;

        -- One commit for both steps.
        COMMIT;

        pkg_log.info(RPAD('DIM_CUSTOMER', 26) || LPAD(l_closed, 9) || ' versions closed, '
                     || l_inserted || ' versions inserted');
    EXCEPTION
        WHEN OTHERS THEN
            fail(p_batch_id, 'PKG_DIM.LOAD_CUSTOMER_SCD2');
            RAISE;
    END load_customer_scd2;

END pkg_dim;
/
