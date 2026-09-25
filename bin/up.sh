#!/usr/bin/env bash
# Start the whole environment (Oracle XE + tools container) and wait until
# the warehouse user can actually log in. Run from Git Bash on the host.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # stop Git Bash on Windows rewriting /paths inside docker arguments

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "ERROR: .env not found. Run: cp .env.example .env   (then set the passwords)"
    exit 1
fi

# Bind-mount targets must exist before the containers start.
mkdir -p logs/ext_logs logs/nightly data/delta data/test

docker compose up -d --build

# "Container running" is not the same as "database accepts connections":
# Oracle needs time to open, and on the very first start it also runs the
# init script that creates the DW user. So test a real login as DW.
echo "Waiting for Oracle to accept logins as the warehouse user (first start can take a few minutes)..."
max_wait=900
waited=0
until docker compose exec -T tools bin/sql.sh -c "SELECT 'DW_READY' AS status FROM dual;" 2>/dev/null | grep -q DW_READY; do
    # If Oracle crashed (e.g. the init script failed), stop waiting right away.
    if [ -z "$(docker compose ps -q --status running oracle)" ]; then
        echo "ERROR: the oracle container is not running. Last log lines:"
        docker compose logs --tail 40 oracle
        exit 1
    fi
    if [ "$waited" -ge "$max_wait" ]; then
        echo "ERROR: database not ready after ${max_wait}s. Last Oracle log lines:"
        docker compose logs --tail 40 oracle
        exit 1
    fi
    sleep 10
    waited=$((waited + 10))
    echo "  still waiting... ${waited}s"
done

echo "Database is ready: warehouse user connected (after ~${waited}s)."
