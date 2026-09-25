CREATE OR REPLACE PACKAGE BODY pkg_stage AS

    -- The table being loaded right now, so an error message can name it.
    g_current_table  VARCHAR2(30);

    -- -------------------------------------------------------------------------
    -- Point every raw-extract external table at the chosen directory object.
    -- The directory name is checked against a fixed list before it is put into
    -- the ALTER statement, so nothing else can ever be injected into the SQL.
    -- (ALTER TABLE is DDL, so it must be run with EXECUTE IMMEDIATE.)
    -- -------------------------------------------------------------------------
    PROCEDURE set_source_dir (p_source_dir IN VARCHAR2)
    IS
        TYPE t_names IS TABLE OF VARCHAR2(30);
        l_tables  t_names := t_names('EXT_CUSTOMERS', 'EXT_ORDERS', 'EXT_ORDER_ITEMS', 'EXT_PAYMENTS',
                                     'EXT_PRODUCTS', 'EXT_SELLERS', 'EXT_CATEGORY_TRANSLATION');
    BEGIN
        IF p_source_dir NOT IN ('RAW_DIR', 'TEST_DIR') THEN
            RAISE_APPLICATION_ERROR(-20010, 'Unknown source directory: ' || p_source_dir
                                            || ' (allowed: RAW_DIR, TEST_DIR)');
        END IF;

        FOR i IN 1 .. l_tables.COUNT LOOP
            EXECUTE IMMEDIATE 'ALTER TABLE ' || l_tables(i) || ' DEFAULT DIRECTORY ' || p_source_dir;
        END LOOP;
    END set_source_dir;


    -- -------------------------------------------------------------------------
    -- Empty one staging table and refill it from its external table.
    --   TRUNCATE instead of DELETE: it resets the table in one quick operation
    --   and produces almost no undo. It is DDL, hence EXECUTE IMMEDIATE, and it
    --   commits implicitly.
    --   INSERT /*+ APPEND */: direct-path insert, written straight above the
    --   table's high-water mark, much faster for bulk loads. Oracle requires a
    --   COMMIT before the same session can read the table again, so we commit.
    -- Staging and external tables have the same columns in the same order,
    -- which is why SELECT * is safe here.
    -- -------------------------------------------------------------------------
    PROCEDURE reload_table (
        p_staging_table   IN VARCHAR2,
        p_external_table  IN VARCHAR2
    )
    IS
        l_rows  NUMBER;
    BEGIN
        g_current_table := p_staging_table;

        EXECUTE IMMEDIATE 'TRUNCATE TABLE ' || p_staging_table;
        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || p_staging_table
                          || ' SELECT * FROM ' || p_external_table;
        l_rows := SQL%ROWCOUNT;
        COMMIT;

        pkg_log.info(RPAD(p_staging_table, 26) || LPAD(l_rows, 9) || ' rows staged');
    END reload_table;


    PROCEDURE load_all (
        p_batch_id    IN NUMBER,
        p_source_dir  IN VARCHAR2 DEFAULT 'RAW_DIR'
    )
    IS
    BEGIN
        g_current_table := NULL;
        set_source_dir(p_source_dir);

        reload_table('STG_CUSTOMER',             'EXT_CUSTOMERS');
        reload_table('STG_ORDER',                'EXT_ORDERS');
        reload_table('STG_ORDER_ITEM',           'EXT_ORDER_ITEMS');
        reload_table('STG_PAYMENT',              'EXT_PAYMENTS');
        reload_table('STG_PRODUCT',              'EXT_PRODUCTS');
        reload_table('STG_SELLER',               'EXT_SELLERS');
        reload_table('STG_CATEGORY_TRANSLATION', 'EXT_CATEGORY_TRANSLATION');
    EXCEPTION
        WHEN OTHERS THEN
            -- Log first (autonomous, survives the rollback), then undo and re-raise
            -- so the orchestrator marks the batch FAILED.
            pkg_log.log_error(p_batch_id, 'PKG_STAGE.LOAD_ALL', g_current_table, SQLCODE,
                              DBMS_UTILITY.FORMAT_ERROR_STACK || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            ROLLBACK;
            RAISE;
    END load_all;


    PROCEDURE load_customer_delta (p_batch_id IN NUMBER)
    IS
    BEGIN
        reload_table('STG_CUSTOMER', 'EXT_CUSTOMER_DELTA');
    EXCEPTION
        WHEN OTHERS THEN
            pkg_log.log_error(p_batch_id, 'PKG_STAGE.LOAD_CUSTOMER_DELTA', 'STG_CUSTOMER', SQLCODE,
                              DBMS_UTILITY.FORMAT_ERROR_STACK || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            ROLLBACK;
            RAISE;
    END load_customer_delta;

END pkg_stage;
/
