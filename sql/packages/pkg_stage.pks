CREATE OR REPLACE PACKAGE pkg_stage AS
/*
    pkg_stage: loads the CSV extract into the staging tables.

    What it does
      For each source file: TRUNCATE the staging table, then copy every row
      from the matching external table with a direct-path insert (APPEND hint).
      After this step the files are never read again; every later step works
      from the staging tables, which hold one consistent snapshot.

    Why it exists
      It separates "get the file into the database" from "transform it into
      the star schema". If a dimension or fact load fails, it can be re-run
      from staging without re-reading files, and a bad file is caught here,
      before any warehouse table is touched.

    Source folder
      External tables read from an Oracle directory object. load_all can point
      them at RAW_DIR (the real extract) or TEST_DIR (deliberately broken copies
      made by the tests). Only those two names are accepted.
*/

    -- Stage all 7 source files from p_source_dir ('RAW_DIR' or 'TEST_DIR').
    PROCEDURE load_all (
        p_batch_id    IN NUMBER,
        p_source_dir  IN VARCHAR2 DEFAULT 'RAW_DIR'
    );

    -- Stage only the customer delta extract (data/delta/customer_delta.csv)
    -- into stg_customer, for the SCD2 change feed.
    PROCEDURE load_customer_delta (p_batch_id IN NUMBER);

END pkg_stage;
/
