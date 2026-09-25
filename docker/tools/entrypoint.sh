#!/bin/bash
# Main process of the tools container: set the timezone, install the crontab
# if the repo has one, then run cron in the foreground (this keeps the container up).
set -e

# cron reads /etc/localtime, not the TZ variable, so link the zone file.
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

if [ -f /work/cron/nightly.cron ]; then
    # tr strips Windows line endings in case the file was edited in Notepad.
    tr -d '\r' < /work/cron/nightly.cron | crontab -
    echo "Installed crontab from /work/cron/nightly.cron"
fi

exec cron -f
