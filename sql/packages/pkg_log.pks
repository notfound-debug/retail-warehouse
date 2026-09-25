CREATE OR REPLACE PACKAGE pkg_log AS
/*
    pkg_log: the ETL logging framework.

    What it does
      - start_batch / finish_batch record every load run in ETL_BATCH.
      - log_error records every error (a single bad row, or a whole failed
        step) in ETL_ERROR_LOG, with the batch, the step and the row's key.
      - info prints a timestamped progress line (DBMS_OUTPUT), which the Bash
        wrapper captures in its log file.

    Why it exists
      Every other package needs to record what happened, and the record must
      survive even when the load itself fails and is rolled back. So the
      procedures that write to the log tables run as AUTONOMOUS TRANSACTIONS:
      they commit their own insert/update independently of the caller.
      Without that, a ROLLBACK after a failure would erase the very error row
      that explains the failure.
*/

    -- Insert a RUNNING row into ETL_BATCH and return its new batch_id.
    FUNCTION start_batch (
        p_feed_name   IN VARCHAR2,
        p_source_dir  IN VARCHAR2
    ) RETURN NUMBER;

    -- Record one error. p_source_key identifies the failing row when there is
    -- one (e.g. 'order_id|order_item_id'); NULL for a step-level failure.
    PROCEDURE log_error (
        p_batch_id       IN NUMBER,
        p_step_name      IN VARCHAR2,
        p_source_key     IN VARCHAR2,
        p_error_code     IN NUMBER,
        p_error_message  IN VARCHAR2
    );

    -- Close the batch: set finish time, final status and the number of errors logged.
    PROCEDURE finish_batch (
        p_batch_id  IN NUMBER,
        p_status    IN VARCHAR2
    );

    -- Print a timestamped progress message.
    PROCEDURE info (p_message IN VARCHAR2);

END pkg_log;
/
