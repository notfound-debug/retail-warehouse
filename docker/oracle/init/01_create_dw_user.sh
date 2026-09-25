#!/bin/bash
# Runs once, the first time the database is created: the gvenzl/oracle-xe image
# executes every *.sh / *.sql file in /container-entrypoint-initdb.d on first start.
#
# Creates:
#   - the warehouse schema user (DW_USER) inside the pluggable database XEPDB1,
#     with only the privileges it needs (no DBA role, not SYSTEM);
#   - the directory objects the external tables read CSV files from.
# Credentials come from the container environment (.env), never hard-coded.
set -e

sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = XEPDB1;

CREATE USER ${DW_USER} IDENTIFIED BY "${DW_PASSWORD}"
    DEFAULT TABLESPACE users
    QUOTA UNLIMITED ON users;

-- Exactly what the warehouse needs: log in, and create tables (incl. external
-- tables), views, sequences and PL/SQL packages in its own schema.
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE
    TO ${DW_USER};

-- Directory objects map a name inside Oracle to a folder on the database server.
-- /data is the repo data/ folder, mounted read-only by docker-compose.
--   raw_dir     Olist CSVs
--   delta_dir   SCD2 customer delta extract
--   test_dir    broken copies made by the tests
--   ext_log_dir external-table .log and .bad files
-- (sqlplus only runs a statement when ';' is the last character on the line,
--  so no comments after the semicolons.)
CREATE OR REPLACE DIRECTORY raw_dir     AS '/data/raw';
CREATE OR REPLACE DIRECTORY delta_dir   AS '/data/delta';
CREATE OR REPLACE DIRECTORY test_dir    AS '/data/test';
CREATE OR REPLACE DIRECTORY ext_log_dir AS '/ext_logs';

GRANT READ        ON DIRECTORY raw_dir     TO ${DW_USER};
GRANT READ        ON DIRECTORY delta_dir   TO ${DW_USER};
GRANT READ        ON DIRECTORY test_dir    TO ${DW_USER};
GRANT READ, WRITE ON DIRECTORY ext_log_dir TO ${DW_USER};

EXIT
EOF

echo "Created warehouse user ${DW_USER} and directory objects in XEPDB1."
