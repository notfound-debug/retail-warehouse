-- =============================================================================
-- install_packages.sql
-- Compiles all PL/SQL packages (spec before body, dependencies first).
-- CREATE OR REPLACE makes this safe to re-run on its own after editing a package:
--   bin/sql.sh sql/packages/install_packages.sql
-- =============================================================================

PROMPT   pkg_log
@sql/packages/pkg_log.pks
@sql/packages/pkg_log.pkb
PROMPT   pkg_stage
@sql/packages/pkg_stage.pks
@sql/packages/pkg_stage.pkb
PROMPT   pkg_dim
@sql/packages/pkg_dim.pks
@sql/packages/pkg_dim.pkb
PROMPT   pkg_fact
@sql/packages/pkg_fact.pks
@sql/packages/pkg_fact.pkb
PROMPT   pkg_etl
@sql/packages/pkg_etl.pks
@sql/packages/pkg_etl.pkb

-- sqlplus only prints a warning when PL/SQL compiles with errors; it does not
-- fail. So list any errors and then fail the install explicitly.
SET HEADING ON PAGESIZE 100 LINESIZE 200
COLUMN name FORMAT A12
COLUMN text FORMAT A120
SELECT name, type, line, position, text FROM user_errors ORDER BY name, type, sequence;

DECLARE
    l_errors  NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_errors FROM user_errors;
    IF l_errors > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, l_errors || ' PL/SQL compilation error(s); see the list above.');
    END IF;
END;
/
