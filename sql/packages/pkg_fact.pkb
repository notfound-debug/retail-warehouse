CREATE OR REPLACE PACKAGE BODY pkg_fact AS

    c_fetch_limit  CONSTANT PLS_INTEGER := 10000;
    c_step_name    CONSTANT VARCHAR2(30) := 'PKG_FACT.LOAD_FACT_SALES';

    -- ORA-24381 is raised at the end of a FORALL ... SAVE EXCEPTIONS if any row failed.
    e_bulk_errors  EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_bulk_errors, -24381);

    -- One staged order line with its dimension keys. Values are still text.
    CURSOR c_order_lines IS
        WITH primary_payment AS (
            SELECT order_id, payment_type
            FROM (
                SELECT order_id,
                       payment_type,
                       ROW_NUMBER() OVER (
                           PARTITION BY order_id
                           ORDER BY TO_NUMBER(payment_value DEFAULT NULL ON CONVERSION ERROR) DESC NULLS LAST,
                                    TO_NUMBER(payment_sequential DEFAULT NULL ON CONVERSION ERROR)
                       ) AS rn
                FROM stg_payment
            )
            WHERE rn = 1
        )
        SELECT i.order_id,
               i.order_item_id,
               i.price,
               i.freight_value,
               o.order_status,
               o.order_purchase_timestamp,
               o.order_delivered_customer_date,
               o.order_estimated_delivery_date,
               NVL(dc.customer_key, -1)      AS customer_key,
               NVL(dp.product_key, -1)       AS product_key,
               NVL(ds.seller_key, -1)        AS seller_key,
               NVL(dpt.payment_type_key, -1) AS payment_type_key
        FROM stg_order_item i
        -- LEFT JOINs everywhere: a line whose order or dimension row is missing
        -- is still processed (and fails or gets -1) instead of silently vanishing.
        LEFT JOIN stg_order        o   ON o.order_id = i.order_id
        LEFT JOIN stg_customer     c   ON c.customer_id = o.customer_id
        LEFT JOIN dim_customer     dc  ON dc.customer_unique_id = c.customer_unique_id
                                      AND dc.is_current = 'Y'
        LEFT JOIN dim_product      dp  ON dp.product_id = i.product_id
        LEFT JOIN dim_seller       ds  ON ds.seller_id = i.seller_id
        LEFT JOIN primary_payment  pp  ON pp.order_id = i.order_id
        LEFT JOIN dim_payment_type dpt ON dpt.payment_type_code = pp.payment_type;

    TYPE t_order_lines IS TABLE OF c_order_lines%ROWTYPE;

    -- The same line after conversion: typed exactly like the fact table's columns.
    TYPE t_fact_row IS RECORD (
        order_id                     fact_sales.order_id%TYPE,
        order_item_id                fact_sales.order_item_id%TYPE,
        order_date_key               fact_sales.order_date_key%TYPE,
        delivered_date_key           fact_sales.delivered_date_key%TYPE,
        estimated_delivery_date_key  fact_sales.estimated_delivery_date_key%TYPE,
        customer_key                 fact_sales.customer_key%TYPE,
        product_key                  fact_sales.product_key%TYPE,
        seller_key                   fact_sales.seller_key%TYPE,
        payment_type_key             fact_sales.payment_type_key%TYPE,
        order_status                 fact_sales.order_status%TYPE,
        price                        fact_sales.price%TYPE,
        freight_value                fact_sales.freight_value%TYPE
    );
    TYPE t_fact_rows IS TABLE OF t_fact_row INDEX BY PLS_INTEGER;


    -- -------------------------------------------------------------------------
    -- Bitmap indexes and bulk loads.
    -- Maintaining a bitmap index one row at a time is expensive: each insert
    -- rewrites a compressed bitmap entry that covers many rows. Measured in M3
    -- on the first full load: 224 s with the bitmap indexes in place, versus
    -- 4.2 s for the load plus 0.24 s to rebuild all four afterwards.
    -- So: mark them UNUSABLE before the load (Oracle then skips them) and
    -- REBUILD them from the finished table afterwards. This is the standard
    -- warehouse pattern. B-tree indexes and the primary key stay in place:
    -- the primary key is needed by the MERGE itself.
    -- ALTER INDEX is DDL, so it needs EXECUTE IMMEDIATE and commits implicitly.
    -- -------------------------------------------------------------------------
    PROCEDURE set_bitmap_indexes (p_action IN VARCHAR2)   -- 'UNUSABLE' or 'REBUILD'
    IS
    BEGIN
        FOR ix IN (SELECT index_name FROM user_indexes
                   WHERE table_name = 'FACT_SALES' AND index_type = 'BITMAP') LOOP
            EXECUTE IMMEDIATE 'ALTER INDEX ' || ix.index_name || ' '
                || CASE p_action WHEN 'REBUILD' THEN 'REBUILD' ELSE 'UNUSABLE' END;
        END LOOP;
    END set_bitmap_indexes;


    -- 'YYYY-MM-DD HH24:MI:SS' text -> YYYYMMDD date key. NULL stays NULL
    -- (an order that has not been delivered has no delivered date).
    FUNCTION to_date_key (p_timestamp IN VARCHAR2) RETURN NUMBER
    IS
    BEGIN
        IF p_timestamp IS NULL THEN
            RETURN NULL;
        END IF;
        RETURN TO_NUMBER(TO_CHAR(TO_DATE(p_timestamp, 'YYYY-MM-DD HH24:MI:SS'), 'YYYYMMDD'));
    END to_date_key;


    -- -------------------------------------------------------------------------
    -- Layer 1: convert one staged text line into a typed fact row.
    -- Runs in PL/SQL only (no SQL statement), so looping over the chunk does not
    -- switch to the SQL engine. Returns FALSE, after logging the row, if any
    -- value cannot be converted (e.g. price 'abc').
    --
    -- Why here and not inside the MERGE: a conversion error inside the MERGE's
    -- USING subquery aborts the whole FORALL statement; SAVE EXCEPTIONS does not
    -- catch it (found by the M3 broken-file test). Converting first isolates
    -- bad values row by row.
    -- -------------------------------------------------------------------------
    FUNCTION convert_line (
        p_batch_id  IN  NUMBER,
        p_line      IN  c_order_lines%ROWTYPE,
        p_row       OUT t_fact_row
    ) RETURN BOOLEAN
    IS
    BEGIN
        p_row.order_id                    := p_line.order_id;
        p_row.order_item_id               := TO_NUMBER(p_line.order_item_id);
        p_row.order_date_key              := to_date_key(p_line.order_purchase_timestamp);
        p_row.delivered_date_key          := to_date_key(p_line.order_delivered_customer_date);
        p_row.estimated_delivery_date_key := to_date_key(p_line.order_estimated_delivery_date);
        p_row.customer_key                := p_line.customer_key;
        p_row.product_key                 := p_line.product_key;
        p_row.seller_key                  := p_line.seller_key;
        p_row.payment_type_key            := p_line.payment_type_key;
        p_row.order_status                := p_line.order_status;
        p_row.price                       := TO_NUMBER(p_line.price);
        p_row.freight_value               := TO_NUMBER(p_line.freight_value);
        RETURN TRUE;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_log.log_error(
                p_batch_id      => p_batch_id,
                p_step_name     => c_step_name,
                p_source_key    => p_line.order_id || '|' || p_line.order_item_id,
                p_error_code    => SQLCODE,
                p_error_message => 'Conversion failed: ' || SQLERRM
                    || ' | price=' || p_line.price
                    || ' freight=' || p_line.freight_value
                    || ' purchased=' || p_line.order_purchase_timestamp);
            RETURN FALSE;
    END convert_line;


    PROCEDURE load_fact_sales (
        p_batch_id  IN  NUMBER,
        p_rejected  OUT NUMBER
    )
    IS
        l_lines         t_order_lines;   -- one fetched chunk, as text
        l_rows          t_fact_rows;     -- the same chunk, converted (bad lines left out)
        l_row           t_fact_row;
        l_fetched       NUMBER := 0;
        l_rows_before   NUMBER;
        l_rows_after    NUMBER;
        l_bad_index     PLS_INTEGER;
        l_error_code    NUMBER;
    BEGIN
        p_rejected := 0;
        SELECT COUNT(*) INTO l_rows_before FROM fact_sales;

        set_bitmap_indexes('UNUSABLE');

        OPEN c_order_lines;
        LOOP
            FETCH c_order_lines BULK COLLECT INTO l_lines LIMIT c_fetch_limit;
            EXIT WHEN l_lines.COUNT = 0;
            l_fetched := l_fetched + l_lines.COUNT;

            -- Layer 1: convert. Good rows go into l_rows, numbered 1..n with no gaps.
            l_rows.DELETE;
            FOR i IN 1 .. l_lines.COUNT LOOP
                IF convert_line(p_batch_id, l_lines(i), l_row) THEN
                    l_rows(l_rows.COUNT + 1) := l_row;
                ELSE
                    p_rejected := p_rejected + 1;
                END IF;
            END LOOP;

            -- Layer 2: write the whole chunk with one FORALL. SAVE EXCEPTIONS
            -- collects database-level row errors (e.g. a date outside dim_date
            -- violates the foreign key) instead of stopping at the first one.
            BEGIN
                FORALL i IN 1 .. l_rows.COUNT SAVE EXCEPTIONS
                    MERGE INTO fact_sales f
                    USING (
                        SELECT l_rows(i).order_id                     AS order_id,
                               l_rows(i).order_item_id                AS order_item_id,
                               l_rows(i).order_date_key               AS order_date_key,
                               l_rows(i).delivered_date_key           AS delivered_date_key,
                               l_rows(i).estimated_delivery_date_key  AS estimated_delivery_date_key,
                               l_rows(i).customer_key                 AS customer_key,
                               l_rows(i).product_key                  AS product_key,
                               l_rows(i).seller_key                   AS seller_key,
                               l_rows(i).payment_type_key             AS payment_type_key,
                               l_rows(i).order_status                 AS order_status,
                               l_rows(i).price                        AS price,
                               l_rows(i).freight_value                AS freight_value
                        FROM dual
                    ) s
                    ON (f.order_id = s.order_id AND f.order_item_id = s.order_item_id)
                    -- Existing line: only fields that legitimately change after the
                    -- order is placed. customer_key is deliberately never updated:
                    -- a sale keeps the customer version it was loaded with (SCD2).
                    WHEN MATCHED THEN UPDATE
                        SET f.order_status       = s.order_status,
                            f.delivered_date_key = s.delivered_date_key,
                            f.load_batch_id      = p_batch_id
                        WHERE DECODE(f.order_status, s.order_status, 0, 1) = 1
                           OR DECODE(f.delivered_date_key, s.delivered_date_key, 0, 1) = 1
                    WHEN NOT MATCHED THEN INSERT (
                        order_id, order_item_id, order_date_key, delivered_date_key,
                        estimated_delivery_date_key, customer_key, product_key, seller_key,
                        payment_type_key, order_status, price, freight_value, load_batch_id
                    ) VALUES (
                        s.order_id, s.order_item_id, s.order_date_key, s.delivered_date_key,
                        s.estimated_delivery_date_key, s.customer_key, s.product_key, s.seller_key,
                        s.payment_type_key, s.order_status, s.price, s.freight_value, p_batch_id
                    );
            EXCEPTION
                WHEN e_bulk_errors THEN
                    -- The good rows of this chunk are already merged. Log each bad one.
                    FOR j IN 1 .. SQL%BULK_EXCEPTIONS.COUNT LOOP
                        l_bad_index  := SQL%BULK_EXCEPTIONS(j).ERROR_INDEX;
                        l_error_code := SQL%BULK_EXCEPTIONS(j).ERROR_CODE;
                        pkg_log.log_error(
                            p_batch_id      => p_batch_id,
                            p_step_name     => c_step_name,
                            p_source_key    => l_rows(l_bad_index).order_id || '|' || l_rows(l_bad_index).order_item_id,
                            p_error_code    => -l_error_code,
                            p_error_message => 'Write failed: ' || SQLERRM(-l_error_code));
                    END LOOP;
                    p_rejected := p_rejected + SQL%BULK_EXCEPTIONS.COUNT;
            END;
        END LOOP;
        CLOSE c_order_lines;

        COMMIT;
        set_bitmap_indexes('REBUILD');

        SELECT COUNT(*) INTO l_rows_after FROM fact_sales;
        pkg_log.info(RPAD('FACT_SALES', 26) || LPAD(l_fetched, 9) || ' lines read, '
                     || (l_rows_after - l_rows_before) || ' inserted, '
                     || p_rejected || ' rejected (see ETL_ERROR_LOG)');
    EXCEPTION
        WHEN OTHERS THEN
            -- Anything other than row-level errors: log, undo the whole fact step, re-raise.
            pkg_log.log_error(p_batch_id, c_step_name, NULL, SQLCODE,
                              DBMS_UTILITY.FORMAT_ERROR_STACK || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            IF c_order_lines%ISOPEN THEN
                CLOSE c_order_lines;
            END IF;
            ROLLBACK;
            -- Never leave the bitmap indexes unusable after a failure.
            set_bitmap_indexes('REBUILD');
            RAISE;
    END load_fact_sales;

END pkg_fact;
/
