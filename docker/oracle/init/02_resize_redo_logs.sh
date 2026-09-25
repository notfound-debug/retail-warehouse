#!/bin/bash
# Runs once, on the database's first start (after 01_create_dw_user.sh).
#
# Why: the gvenzl "slim" image ships with only two 10 MB redo log groups.
# A bulk load fills 10 MB in seconds, and Oracle cannot reuse a log until the
# checkpoint for it has finished, so every switch stalls the load
# ("log file switch (checkpoint incomplete)"). Measured in M3: the fact MERGE
# ran for 326 s but used only 22 s of CPU, and the database had spent 380 s
# waiting on exactly that event.
# Fix: three 200 MB groups, then drop the two tiny ones.
#
# Safe to run again: groups that already exist are skipped, and groups
# already dropped are ignored. To apply it to an existing database:
#   docker compose exec oracle bash /container-entrypoint-initdb.d/02_resize_redo_logs.sh
set -e

sqlplus -s / as sysdba <<'EOF'
WHENEVER SQLERROR EXIT FAILURE
DECLARE
    PROCEDURE add_group (p_group IN NUMBER) IS
        l_count  NUMBER;
    BEGIN
        SELECT COUNT(*) INTO l_count FROM v$log WHERE group# = p_group;
        IF l_count = 0 THEN
            EXECUTE IMMEDIATE 'ALTER DATABASE ADD LOGFILE GROUP ' || p_group
                || ' (''/opt/oracle/oradata/XE/redo0' || p_group || '.log'') SIZE 200M';
        END IF;
    END add_group;

    -- A group can only be dropped once it is INACTIVE (not being written, and
    -- no longer needed for crash recovery). Switch and checkpoint until it is.
    PROCEDURE drop_group (p_group IN NUMBER) IS
        l_status  VARCHAR2(16);
    BEGIN
        FOR attempt IN 1 .. 10 LOOP
            BEGIN
                SELECT status INTO l_status FROM v$log WHERE group# = p_group;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RETURN;   -- already dropped
            END;
            IF l_status IN ('INACTIVE', 'UNUSED') THEN
                EXECUTE IMMEDIATE 'ALTER DATABASE DROP LOGFILE GROUP ' || p_group;
                RETURN;
            END IF;
            EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE';
            EXECUTE IMMEDIATE 'ALTER SYSTEM CHECKPOINT';
        END LOOP;
        RAISE_APPLICATION_ERROR(-20001, 'Could not drop redo log group ' || p_group);
    END drop_group;
BEGIN
    add_group(3);
    add_group(4);
    add_group(5);
    drop_group(1);
    drop_group(2);
END;
/
EXIT
EOF

# DROP LOGFILE removes the group from the database but leaves the file on disk.
rm -f /opt/oracle/oradata/XE/redo01.log /opt/oracle/oradata/XE/redo02.log

echo "Redo logs resized: 3 groups x 200 MB."
