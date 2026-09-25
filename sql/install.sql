-- =============================================================================
-- install.sql
-- Builds the whole warehouse schema in dependency order. Run through
-- bin/install.sh (which connects as the DW user). File paths are relative to
-- the repo root: bin/sql.sh always runs sqlplus from there. (This sqlplus
-- resolves @@ relative to the current directory, not to this file, so plain
-- root-relative @ paths are the clearer choice.)
-- =============================================================================
SET ECHO OFF FEEDBACK OFF

PROMPT [1/8] ETL audit tables
@sql/ddl/01_etl_tables.sql
PROMPT [2/8] External tables
@sql/ddl/02_external_tables.sql
PROMPT [3/8] Staging tables
@sql/ddl/03_staging_tables.sql
PROMPT [4/8] Sequences
@sql/ddl/04_sequences.sql
PROMPT [5/8] Dimension tables
@sql/ddl/05_dimensions.sql
PROMPT [6/8] Fact table
@sql/ddl/06_fact.sql
PROMPT [7/8] Fact indexes
@sql/ddl/07_indexes.sql
PROMPT [8/8] Populate dim_date
@sql/ddl/08_populate_dim_date.sql

PROMPT Install complete.
