-- =============================================================================
-- reset_schema.sql
-- Drops EVERY object in the connected schema (tables, views, sequences,
-- packages), giving a clean, empty schema. All warehouse data is lost.
-- Used by `bin/install.sh --reset` and by the test suite.
-- It only ever touches the schema you are connected as (USER_OBJECTS).
-- =============================================================================
SET FEEDBACK OFF

BEGIN
    FOR obj IN (
        SELECT object_name, object_type
        FROM   user_objects
        WHERE  object_type IN ('VIEW', 'PACKAGE', 'PROCEDURE', 'FUNCTION', 'SEQUENCE', 'TABLE')
        ORDER  BY object_type, object_name
    ) LOOP
        EXECUTE IMMEDIATE 'DROP ' || obj.object_type || ' "' || obj.object_name || '"'
            || CASE WHEN obj.object_type = 'TABLE' THEN ' CASCADE CONSTRAINTS PURGE' END;
    END LOOP;
END;
/

PROMPT Schema reset: all objects dropped.
