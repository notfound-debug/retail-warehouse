-- =============================================================================
-- grant_report_access.sql
-- Grants SELECT on every report view (V_RPT_*) and reference view (V_REF_*,
-- key lists for pre-load checks) to the role DW_REPORTING, which
-- the read-only reporting user holds (docker/oracle/init/03_create_report_user.sh).
-- Only the views: the role gets no access to fact, dimension, staging or ETL
-- tables. A view runs with its owner's rights, so the grantee can read the view
-- without any grant on the tables underneath it.
-- The owner of an object can grant access to it without any special privilege.
-- If the role does not exist on this database, a note is printed and nothing fails.
-- =============================================================================
DECLARE
    e_no_such_role  EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_no_such_role, -1917);   -- ORA-01917: user or role does not exist
    l_granted       PLS_INTEGER := 0;
BEGIN
    FOR v IN (SELECT view_name FROM user_views
              WHERE view_name LIKE 'V\_RPT\_%' ESCAPE '\'
                 OR view_name LIKE 'V\_REF\_%' ESCAPE '\'
              ORDER BY view_name) LOOP
        EXECUTE IMMEDIATE 'GRANT SELECT ON ' || v.view_name || ' TO dw_reporting';
        l_granted := l_granted + 1;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('  SELECT granted to DW_REPORTING on ' || l_granted || ' views');
EXCEPTION
    WHEN e_no_such_role THEN
        DBMS_OUTPUT.PUT_LINE('  Role DW_REPORTING does not exist; no reporting grants made '
            || '(see docker/oracle/init/03_create_report_user.sh).');
END;
/
