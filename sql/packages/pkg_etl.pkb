CREATE OR REPLACE PACKAGE BODY pkg_etl AS

    -- The batch's start time is the SCD2 effective date, so read it back from
    -- ETL_BATCH rather than calling SYSDATE again (which could differ by seconds).
    FUNCTION batch_start_time (p_batch_id IN NUMBER) RETURN DATE
    IS
        l_started_at  DATE;
    BEGIN
        SELECT started_at INTO l_started_at FROM etl_batch WHERE batch_id = p_batch_id;
        RETURN l_started_at;
    END batch_start_time;


    -- After large changes the optimizer needs fresh row counts to choose good
    -- plans for the report views.
    PROCEDURE refresh_statistics
    IS
    BEGIN
        FOR t IN (SELECT table_name FROM user_tables
                  WHERE table_name = 'FACT_SALES' OR table_name LIKE 'DIM\_%' ESCAPE '\') LOOP
            DBMS_STATS.GATHER_TABLE_STATS(ownname => USER, tabname => t.table_name);
        END LOOP;
        pkg_log.info('Optimizer statistics refreshed on fact and dimension tables');
    END refresh_statistics;


    FUNCTION run_full_load (p_source_dir IN VARCHAR2 DEFAULT 'RAW_DIR') RETURN NUMBER
    IS
        l_batch_id  NUMBER;
        l_rejected  NUMBER;
    BEGIN
        l_batch_id := pkg_log.start_batch('FULL', p_source_dir);

        -- 1. Files -> staging
        pkg_stage.load_all(l_batch_id, p_source_dir);

        -- 2. Dimensions (independent of each other; all must finish before the fact)
        pkg_dim.load_payment_type(l_batch_id);
        pkg_dim.load_product(l_batch_id);
        pkg_dim.load_seller(l_batch_id);
        pkg_dim.load_customer_scd2(l_batch_id, batch_start_time(l_batch_id));

        -- 3. Fact
        pkg_fact.load_fact_sales(l_batch_id, l_rejected);

        refresh_statistics;

        IF l_rejected > 0 THEN
            pkg_log.finish_batch(l_batch_id, 'SUCCESS_WITH_ERRORS');
            RETURN 2;
        END IF;

        pkg_log.finish_batch(l_batch_id, 'SUCCESS');
        RETURN 0;
    EXCEPTION
        WHEN OTHERS THEN
            -- The failing step has already logged the error and rolled back.
            ROLLBACK;
            IF l_batch_id IS NOT NULL THEN
                pkg_log.finish_batch(l_batch_id, 'FAILED');
            END IF;
            RAISE;
    END run_full_load;


    FUNCTION run_customer_delta RETURN NUMBER
    IS
        l_batch_id  NUMBER;
    BEGIN
        l_batch_id := pkg_log.start_batch('CUSTOMER_DELTA', 'DELTA_DIR');

        pkg_stage.load_customer_delta(l_batch_id);
        pkg_dim.load_customer_scd2(l_batch_id, batch_start_time(l_batch_id));

        pkg_log.finish_batch(l_batch_id, 'SUCCESS');
        RETURN 0;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            IF l_batch_id IS NOT NULL THEN
                pkg_log.finish_batch(l_batch_id, 'FAILED');
            END IF;
            RAISE;
    END run_customer_delta;

END pkg_etl;
/
