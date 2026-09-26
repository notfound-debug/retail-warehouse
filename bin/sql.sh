#!/usr/bin/env bash
# Run SQL as the warehouse user with sqlplus. Runs inside the tools container.
#
#   bin/sql.sh sql/some_script.sql [script args...]   (path relative to the repo root)
#   bin/sql.sh -c "SELECT COUNT(*) FROM fact_sales;"
#
# The password is sent to sqlplus on stdin (CONNECT inside the heredoc),
# never as a command-line argument, so it does not appear in `ps` output.
# Exits non-zero if any SQL or PL/SQL statement fails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Run from the repo root so every @sql/... path inside SQL scripts resolves the same way.
cd "$ROOT"
# Load credentials. tr removes Windows line endings in case .env was edited in Notepad.
set -a
source <(tr -d '\r' < "$ROOT/.env")
set +a

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
CONNECT ${DW_USER}/"${DW_PASSWORD}"@//${DW_CONNECT}
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200 PAGESIZE 100 NUMWIDTH 15
$body
EXIT
EOF
