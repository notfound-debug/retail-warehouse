#!/bin/bash
# Runs once, on the database's first start (after 02_resize_redo_logs.sh).
#
# Creates read-only access for other applications (e.g. a reporting portal):
#   * role DW_REPORTING: sql/views/grant_report_access.sql (run by the warehouse
#     install) grants it SELECT on the 12 DW.V_RPT_* views, and nothing else;
#   * user REPORT_USER (from .env): may log in and holds DW_REPORTING.
# The user cannot see the fact/dimension tables, staging, or ETL tables, and
# cannot change anything. Applications query e.g. dw.v_rpt_monthly_revenue.
#
# Safe to run again (existing role/user are kept). To apply it to an existing
# database, from the repo root in Git Bash:
#   set -a; source .env; set +a
#   docker compose exec -T -e REPORT_USER -e REPORT_PASSWORD oracle \
#       bash /container-entrypoint-initdb.d/03_create_report_user.sh
# (-e NAME with no value passes the variable from your shell, so the password
#  never appears on a command line.)
set -e

if [ -z "${REPORT_USER:-}" ] || [ -z "${REPORT_PASSWORD:-}" ]; then
    echo "REPORT_USER / REPORT_PASSWORD not set: no reporting user created."
    exit 0
fi

sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = XEPDB1;

DECLARE
    l_count  NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM dba_roles WHERE role = 'DW_REPORTING';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE ROLE dw_reporting';
    END IF;

    SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = UPPER('${REPORT_USER}');
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER ${REPORT_USER} IDENTIFIED BY "${REPORT_PASSWORD}"';
    END IF;
END;
/

-- Log in, and the reporting role. No quota, no CREATE privileges: it owns nothing.
GRANT CREATE SESSION TO ${REPORT_USER};
GRANT dw_reporting TO ${REPORT_USER};

EXIT
EOF

echo "Reporting user ${REPORT_USER} ready (role DW_REPORTING)."
