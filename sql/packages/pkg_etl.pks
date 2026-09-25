CREATE OR REPLACE PACKAGE pkg_etl AS
/*
    pkg_etl: the orchestrator. The Bash wrapper calls only this package.

    What it does
      run_full_load       start batch -> stage all files -> load the 4 loaded
                          dimensions -> load the fact -> refresh optimizer
                          statistics -> finish batch.
      run_customer_delta  start batch -> stage the customer delta file ->
                          SCD2 customer load -> finish batch.

    Why it exists
      The load order (staging before dimensions, dimensions before the fact) and
      the batch bookkeeping live in one place, in PL/SQL, instead of being spread
      across a Bash script.

    Return codes (the wrapper uses them as its exit code)
      0  success
      2  finished, but some fact rows were rejected and logged (SUCCESS_WITH_ERRORS)
      Any other failure raises an exception: the batch is marked FAILED, the
      error is already in ETL_ERROR_LOG, and sqlplus exits with 1.
*/

    FUNCTION run_full_load (p_source_dir IN VARCHAR2 DEFAULT 'RAW_DIR') RETURN NUMBER;

    FUNCTION run_customer_delta RETURN NUMBER;

END pkg_etl;
/
