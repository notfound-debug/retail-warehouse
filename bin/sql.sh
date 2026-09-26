#!/usr/bin/env bash
# Run SQL with sqlplus. Runs inside the tools container.
#
#   bin/sql.sh sql/some_script.sql [script args...]   (path relative to the repo root)
#   bin/sql.sh -c "SELECT COUNT(*) FROM fact_sales;"
#   bin/sql.sh --report -c "SELECT * FROM dw.v_rpt_monthly_revenue;"
#
# Connects as the warehouse owner (DW_USER) by default, or with --report as the
# read-only reporting user (REPORT_USER), which can only read the DW.V_RPT_* views
# and DW.V_REF_NATURAL_KEYS.
# The password is sent to sqlplus on stdin (CONNECT inside the heredoc),
# never as a command-line argument, so it does not appear in `ps` output.
# Exits non-zero if any SQL or PL/SQL statement fails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Run from the repo root so every @sql/... path inside SQL scripts resolves the same way.
cd "$ROOT"
# Read one setting from .env as plain text. The file is NOT run as shell code
# (no `source`): a value with spaces or symbols, such as a PRELOAD_CHECK command,
# would otherwise be executed. tr removes Windows line endings (Notepad edits).
env_value() {
    grep -m1 "^$1=" "$ROOT/.env" | cut -d= -f2- | tr -d '\r'
}

DW_CONNECT=$(env_value DW_CONNECT)
if [ "${1:-}" = "--report" ]; then
    db_user=$(env_value REPORT_USER)
    db_password=$(env_value REPORT_PASSWORD)
    shift
else
    db_user=$(env_value DW_USER)
    db_password=$(env_value DW_PASSWORD)
fi

if [ "${1:-}" = "-c" ]; then
    body="$2"
else
    body="@$1 ${*:2}"
fi

# ROLLBACK: on an error, sqlplus would otherwise COMMIT the session's pending
# changes before exiting (its default), keeping half of a failed script.
sqlplus -s -L /nolog <<EOF
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
WHENEVER OSERROR EXIT FAILURE ROLLBACK
CONNECT ${db_user}/"${db_password}"@//${DW_CONNECT}
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200 PAGESIZE 100 NUMWIDTH 15
$body
EXIT
EOF
