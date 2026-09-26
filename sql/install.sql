-- =============================================================================
-- install.sql
-- Builds the whole warehouse schema in dependency order. Run through
-- bin/install.sh (which connects as the DW user). File paths are relative to
-- the repo root: bin/sql.sh always runs sqlplus from there. (This sqlplus
-- resolves @@ relative to the current directory, not to this file, so plain
-- root-relative @ paths are the clearer choice.)
-- =============================================================================
SET ECHO OFF FEEDBACK OFF

PROMPT [1/10] ETL audit tables
@sql/ddl/01_etl_tables.sql
PROMPT [2/10] External tables
@sql/ddl/02_external_tables.sql
PROMPT [3/10] Staging tables
@sql/ddl/03_staging_tables.sql
PROMPT [4/10] Sequences
@sql/ddl/04_sequences.sql
PROMPT [5/10] Dimension tables
@sql/ddl/05_dimensions.sql
PROMPT [6/10] Fact table
@sql/ddl/06_fact.sql
PROMPT [7/10] Fact indexes
@sql/ddl/07_indexes.sql
PROMPT [8/10] Populate dim_date
@sql/ddl/08_populate_dim_date.sql
PROMPT [9/10] PL/SQL packages
@sql/packages/install_packages.sql
PROMPT [10/10] Reporting views
@sql/views/install_views.sql

PROMPT Install complete.
