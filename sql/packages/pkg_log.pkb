CREATE OR REPLACE PACKAGE BODY pkg_log AS

    FUNCTION start_batch (
        p_feed_name   IN VARCHAR2,
        p_source_dir  IN VARCHAR2
    ) RETURN NUMBER
    IS
        -- Autonomous: the RUNNING row is committed immediately, so it is
        -- visible (and kept) even if the load that follows fails.
        PRAGMA AUTONOMOUS_TRANSACTION;
        l_batch_id  etl_batch.batch_id%TYPE;
    BEGIN
        l_batch_id := seq_etl_batch.NEXTVAL;

        INSERT INTO etl_batch (batch_id, feed_name, source_dir, started_at, status)
        VALUES (l_batch_id, p_feed_name, p_source_dir, SYSDATE, 'RUNNING');

        COMMIT;
        info('Batch ' || l_batch_id || ' started: feed ' || p_feed_name || ', source ' || p_source_dir);
        RETURN l_batch_id;
    END start_batch;


    PROCEDURE log_error (
        p_batch_id       IN NUMBER,
        p_step_name      IN VARCHAR2,
        p_source_key     IN VARCHAR2,
        p_error_code     IN NUMBER,
        p_error_message  IN VARCHAR2
    )
    IS
        -- Autonomous: this insert commits on its own, so it survives the
        -- caller's ROLLBACK. That is the whole point of the error log.
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO etl_error_log (error_id, batch_id, logged_at, step_name,
                                   source_key, error_code, error_message)
        VALUES (seq_etl_error.NEXTVAL, p_batch_id, SYSDATE, p_step_name,
                SUBSTR(p_source_key, 1, 200), p_error_code, SUBSTR(p_error_message, 1, 4000));

        COMMIT;
    END log_error;


    PROCEDURE finish_batch (
        p_batch_id  IN NUMBER,
        p_status    IN VARCHAR2
    )
    IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        l_error_count  NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO   l_error_count
        FROM   etl_error_log
        WHERE  batch_id = p_batch_id;

        UPDATE etl_batch
        SET    finished_at = SYSDATE,
               status      = p_status,
               error_count = l_error_count
        WHERE  batch_id = p_batch_id;

        COMMIT;
        info('Batch ' || p_batch_id || ' finished: ' || p_status || ', errors logged: ' || l_error_count);
    END finish_batch;


    PROCEDURE info (p_message IN VARCHAR2)
    IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || '  ' || p_message);
    END info;


    PROCEDURE fail_abandoned_batches
    IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        FOR b IN (SELECT batch_id FROM etl_batch WHERE status = 'RUNNING' ORDER BY batch_id) LOOP
            INSERT INTO etl_error_log (error_id, batch_id, logged_at, step_name, error_message)
            VALUES (seq_etl_error.NEXTVAL, b.batch_id, SYSDATE, 'PKG_LOG.FAIL_ABANDONED_BATCHES',
                    'Batch was still RUNNING when the next load started: its process was killed '
                    || 'or lost its database connection before it could record an outcome.');

            UPDATE etl_batch
            SET    status      = 'FAILED',
                   finished_at = SYSDATE,
                   error_count = (SELECT COUNT(*) FROM etl_error_log WHERE batch_id = b.batch_id)
            WHERE  batch_id = b.batch_id;

            info('Abandoned batch ' || b.batch_id || ' was still RUNNING; marked FAILED');
        END LOOP;
        COMMIT;
    END fail_abandoned_batches;

END pkg_log;
/
