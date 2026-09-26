#!/usr/bin/env bash
# =============================================================================
# nightly_load.sh: run one warehouse load safely, from cron or by hand.
# Runs inside the tools container.
#
#   bin/nightly_load.sh                    full load from data/raw   (directory RAW_DIR)
#   bin/nightly_load.sh --delta            SCD2 customer delta from data/delta
#   bin/nightly_load.sh --source TEST_DIR  full load from another directory object (used by tests)
#
# What it guarantees
#   * Only one load at a time: a lock file holds the PID of the running load.
#     A lock left behind by a process that no longer exists (a "stale" lock,
#     e.g. after a crash) is detected and removed.
#   * Every run writes its own log file: logs/nightly/nightly_YYYYMMDD_HHMMSS.log.
#     Only the newest 14 are kept (log rotation).
#   * The exit code tells cron / a monitoring tool what happened:
#       0  success
#       1  the load failed (details in the log file and in ETL_ERROR_LOG)
#       2  the load finished but rejected some rows (see ETL_ERROR_LOG)
#       3  skipped: another load is still running
#       4  wrong command-line arguments
# =============================================================================
set -uo pipefail   # no "set -e": failures are handled explicitly so they are always logged

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$ROOT/logs/nightly"
LOCK_FILE="$ROOT/logs/nightly.lock"
KEEP_LOGS=14

# cron starts jobs with a minimal PATH that does not include /usr/local/bin (sqlplus).
export PATH="/usr/local/bin:$PATH"

# ---- arguments --------------------------------------------------------------
MODE="full"
SOURCE_DIR="RAW_DIR"
while [ $# -gt 0 ]; do
    case "$1" in
        --delta)  MODE="delta"; shift ;;
        --source) SOURCE_DIR="${2:-}"; shift 2 ;;
        *)        echo "Usage: $0 [--delta | --source DIRECTORY_OBJECT]"; exit 4 ;;
    esac
done
# Only plain names like RAW_DIR; the PL/SQL package also checks against a fixed list.
if ! [[ "$SOURCE_DIR" =~ ^[A-Z_]+$ ]]; then
    echo "Invalid --source '$SOURCE_DIR': expected an Oracle directory name such as RAW_DIR"
    exit 4
fi

# ---- log file and rotation --------------------------------------------------
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/nightly_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $*" >> "$LOG_FILE"
}

# Keep the newest $KEEP_LOGS run logs (this run's included), delete older ones.
# ls -t sorts newest first; tail -n +15 lists everything from the 15th onward.
rotate_logs() {
    ls -1t "$LOG_DIR"/nightly_*.log 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | while read -r old; do
        rm -f -- "$old"
    done
}

# One line on stdout per run (this is what ends up in cron.log); details stay in $LOG_FILE.
finish() {
    local code=$1 message=$2
    log "$message (exit code $code)"
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $message (exit $code) - log: ${LOG_FILE#$ROOT/}"
    exit "$code"
}

log "nightly_load.sh started: mode=$MODE source=$SOURCE_DIR pid=$$"
rotate_logs

# ---- lock file --------------------------------------------------------------
# "set -o noclobber" makes > fail if the file already exists, so creating the
# lock is a single atomic step: two runs starting at the same moment cannot
# both succeed.
take_lock() {
    ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null
}

if ! take_lock; then
    other_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    # kill -0 sends no signal; it only checks whether that process exists.
    if [ -n "$other_pid" ] && kill -0 "$other_pid" 2>/dev/null; then
        finish 3 "SKIPPED: another load is running (PID $other_pid, lock $LOCK_FILE)"
    fi
    log "Stale lock found (PID '${other_pid}' is not running): removing it"
    rm -f "$LOCK_FILE"
    if ! take_lock; then
        finish 3 "SKIPPED: another load took the lock at the same moment"
    fi
fi
# From here on we own the lock; release it however the script ends.
trap 'rm -f "$LOCK_FILE"' EXIT

# ---- run the load -----------------------------------------------------------
if [ "$MODE" = "delta" ]; then
    call="pkg_etl.run_customer_delta"
else
    call="pkg_etl.run_full_load('$SOURCE_DIR')"
fi
log "Calling $call"

# pkg_etl returns 0 or 2; sqlplus passes it on with EXIT :rc. Any SQL error
# makes sqlplus exit 1 (WHENEVER SQLERROR in bin/sql.sh).
"$ROOT/bin/sql.sh" -c "
EXEC pkg_log.fail_abandoned_batches
VARIABLE rc NUMBER
EXEC :rc := $call
EXIT :rc" >> "$LOG_FILE" 2>&1
rc=$?

case $rc in
    0) finish 0 "SUCCESS: $MODE load finished" ;;
    2) finish 2 "WARNING: $MODE load finished but rejected rows; see ETL_ERROR_LOG" ;;
    *) finish 1 "FAILED: $MODE load failed (sqlplus exit code $rc); see this log and ETL_ERROR_LOG" ;;
esac
