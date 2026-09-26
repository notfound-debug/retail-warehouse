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

# "Container running" is not the same as "database ready":
# Oracle needs time to open, and on the very first start it also runs the
# init scripts (create the DW user, resize the redo logs). Two conditions:
#   1. the image has printed DATABASE IS READY TO USE, which happens only after
#      every init script has finished (the DW user can log in before the redo
#      log script is done, so a login alone is not enough on first start);
#   2. a real login as DW works.
db_ready() {
    docker compose logs oracle 2>/dev/null | grep -q "DATABASE IS READY TO USE" &&
    docker compose exec -T tools bin/sql.sh -c "SELECT 'DW_READY' AS status FROM dual;" 2>/dev/null | grep -q DW_READY
}

echo "Waiting for Oracle to accept logins as the warehouse user (first start can take a few minutes)..."
max_wait=900
waited=0
until db_ready; do
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
