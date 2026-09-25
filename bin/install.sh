#!/usr/bin/env bash
# Build the warehouse schema (tables, date dimension, and later packages and views).
# Runs inside the tools container:
#   docker compose exec tools bin/install.sh           install into an empty schema
#   docker compose exec tools bin/install.sh --reset   drop every DW object first (ALL DATA IS LOST)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--reset" ]; then
    bin/sql.sh sql/reset_schema.sql
else
    # Refuse to install on top of an existing schema; CREATE TABLE would fail halfway.
    existing=$(bin/sql.sh -c "SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM user_objects;" | tr -d '[:space:]')
    if [ "$existing" != "0" ]; then
        echo "ERROR: schema already has $existing objects. Use --reset to drop them and reinstall."
        exit 1
    fi
fi

bin/sql.sh sql/install.sql
