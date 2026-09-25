#!/usr/bin/env bash
# Stop both containers. The database volume is kept, so data survives.
# To delete the database completely as well: docker compose down -v
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down
