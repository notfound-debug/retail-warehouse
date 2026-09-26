# Retail Sales Data Warehouse: Design

Status: **approved 2026-09-26**. All 9 open questions in section l were resolved with the recommended option (see "Decisions" at the end).

All numbers below were measured on the actual files in `data/raw/` (Olist, 9 CSVs) during discovery.

| File | Records | Used? |
|---|---:|---|
| olist_orders_dataset.csv | 99,441 | yes |
| olist_order_items_dataset.csv | 112,650 | yes (fact grain) |
| olist_order_payments_dataset.csv | 103,886 | yes |
| olist_customers_dataset.csv | 99,441 rows / 96,096 distinct people | yes |
| olist_products_dataset.csv | 32,951 | yes |
| olist_sellers_dataset.csv | 3,095 | yes |
| product_category_name_translation.csv | 71 | yes |
| olist_order_reviews_dataset.csv | 99,224 (104,719 lines: messages contain newlines) | no, see below |
| olist_geolocation_dataset.csv | 1,000,163 | no, see below |

Reviews and geolocation are not needed by any of the 12 reports. Leaving them out keeps the model at exactly 1 fact + 5 dimensions and avoids parsing multi-line review text.

---

## a. Overview

1. This is an Oracle 21c XE star-schema warehouse built from the Olist Brazilian e-commerce dataset (about 99K orders and 112K order line items, 2016-09 to 2018-10).
2. Raw CSVs sit in `data/raw/`. Oracle reads them through **external tables**, and a PL/SQL package copies them into all-VARCHAR2 **staging tables**.
3. PL/SQL packages `MERGE` staging into **5 dimensions** (one of them SCD Type 2 on customers) and **1 fact table** at order-line grain.
4. The fact load uses `BULK COLLECT ... LIMIT` + `FORALL ... SAVE EXCEPTIONS`, so one bad row is logged and skipped instead of killing the load.
5. Every run is a **batch**, recorded in `etl_batch`. Every error goes to `etl_error_log` through an autonomous-transaction procedure, so the log survives rollbacks.
6. The Bash wrapper `bin/nightly_load.sh` runs the load under a lock file, writes a timestamped log, keeps the last 14 logs, and exits non-zero on failure. cron calls it nightly.
7. **12 reporting views** (`v_rpt_*`) answer one business question each, using window functions, CTEs, ROLLUP/CUBE/GROUPING SETS and PIVOT.
8. sqlplus spools two of those views to CSV in `tableau/`. You build the two Tableau Public dashboards from those CSVs. Tableau Public cannot connect to Oracle directly.
9. Everything runs in two Docker containers: `oracle` (the database) and `tools` (Bash, cron, sqlplus). Nothing needs to be installed on Windows except Docker Desktop and Git Bash, which you already have.

## b. System design diagram

```
 HOST (Windows 11)                          DOCKER
 ─────────────────                          ──────────────────────────────────────────────────────────────
 data/raw/*.csv  ──(bind mount /data, read-only)──┐
 data/delta/*.csv ─────────────────────────────── │
                                                  ▼
                              ┌──────────────── oracle container (21c XE, PDB XEPDB1, schema DW) ─────────────┐
                              │                                                                               │
                              │  EXTERNAL TABLES          STAGING (VARCHAR2)       STAR SCHEMA                │
                              │  ext_orders       ──►     stg_order        ──┐                                │
                              │  ext_order_items  ──►     stg_order_item   ──┤   dim_date     (generated)     │
                              │  ext_payments     ──►     stg_payment      ──┤   dim_customer (SCD2)          │
                              │  ext_customers    ──►     stg_customer     ──┼─► dim_product                   │
                              │  ext_customer_delta ─►  (same table)       ──┤   dim_seller                    │
                              │  ext_products     ──►     stg_product      ──┤   dim_payment_type              │
                              │  ext_sellers      ──►     stg_seller       ──┤          │                      │
                              │  ext_category_tr  ──►     stg_category_tr  ──┘          ▼                      │
                              │        pkg_stage                pkg_dim          fact_sales ◄── pkg_fact       │
                              │                                                         │                      │
                              │  pkg_log ──► etl_batch, etl_error_log                   ▼                      │
                              │     ▲   (autonomous transactions)              12 views v_rpt_*                │
                              │     │                                                   │                      │
                              └─────┼───────────────────────────────────────────────────┼──────────────────────┘
                                    │ errors from every package                         │ sqlplus spool
                              ┌─────┴──────────── tools container (Debian + sqlplus + cron) ───────────────────┐
                              │  cron 02:00 ──► bin/nightly_load.sh ──► sqlplus: EXEC pkg_etl.run_full_load     │
                              │                   │  lock file  logs/nightly.lock (stale-PID check)            │
                              │                   │  log file   logs/nightly/nightly_YYYYMMDD_HHMMSS.log       │
                              │                   └─ rotation   keep newest 14                               │
                              │  bin/export_tableau.sh ──► tableau/revenue_trend.csv, cohort_retention.csv ──┼──► Tableau Public
                              └───────────────────────────────────────────────────────────────────────────────┘      (on host)
```

## c. Environment decision

**Recommendation: a small Debian-based `tools` container (Oracle Instant Client + sqlplus + cron), defined in `docker-compose.yml`. No WSL Ubuntu.**

Discovery showed:
- Docker Desktop 29.6.1 and Compose v5.3.0 work, with 16 CPUs, about 8 GB RAM and 281 GB free.
- WSL2 has only the `docker-desktop` internal distro. There is no Ubuntu, so using WSL would mean installing one.
- There is no sqlplus or Instant Client on the host, and Windows has no `cron` or `make`.
- Git Bash 5.3 is available on the host.

Why the container:
1. **Nothing to install on your laptop.** WSL would need an Ubuntu install plus a manual Instant Client install inside it. That setup can't be committed to the repo, and anyone cloning the repo would have to repeat it.
2. **Reproducible.** The Dockerfile *is* the setup documentation: Instant Client version, cron and the timezone are all pinned in code.
3. **cron lives next to the thing it schedules.** The container starts `cron -f` as its main process with `cron/nightly.cron` installed.
4. **One network.** `tools` reaches the database at `oracle:1521/XEPDB1` by service name. No port juggling.

Trade-off: cron only fires while Docker Desktop is running. If the laptop is off at 02:00 the run is skipped, because there's no catch-up like anacron. On a real server this would be a Linux host or a scheduler.

What runs where:
- **Host (Git Bash):** only `./bin/up.sh` and `./bin/down.sh`, which wrap `docker compose`.
- **tools container:** every other script, called as `docker compose exec tools bin/<script>.sh`. Examples: `nightly_load.sh`, `install.sh`, `make_delta.sh`, `export_tableau.sh`, `tests/run_all.sh`.

Database image: `gvenzl/oracle-xe:21-slim`. This is a community image maintained by an Oracle product manager and is the standard image used by Testcontainers. It is smaller and starts faster than Oracle's official `container-registry.oracle.com/database/express:21.3.0-xe`, and it has a built-in health check. (Open question 8.)

Schema user: `DW`, created by an explicit init script `docker/oracle/init/01_create_dw_user.sql`. The script lists every grant, so you can explain each one: `CREATE SESSION`, `CREATE TABLE`, `CREATE VIEW`, `CREATE SEQUENCE`, `CREATE PROCEDURE`, a quota on USERS, and READ/WRITE on the directory objects. It doesn't use SYSTEM or DBA.

## d. Dimensional model

**Grain: one row in `fact_sales` for each line item of each order, meaning one row of `olist_order_items_dataset.csv` (112,650 rows expected).**

Orders with no items (775 of them, all canceled or unavailable) do not appear in the fact table, because there is no line item to record.

### Surrogate key strategy
- **Sequences** (`seq_dim_customer`, `seq_dim_product`, `seq_dim_seller`, `seq_dim_payment_type`), not IDENTITY. Sequences are the classic Oracle idiom and work directly inside `MERGE ... WHEN NOT MATCHED THEN INSERT (seq.NEXTVAL, ...)`. They also let us insert a fixed **-1 "Unknown" row** in each dimension, which `GENERATED ALWAYS AS IDENTITY` would forbid.
- **Unknown member (-1):** if a fact row can't find its dimension row, it gets key -1 instead of being dropped or failing its foreign key. Example: 1 order has items but no payment row.
- **dim_date uses `date_key = YYYYMMDD` (NUMBER(8)).** This is the one deliberate exception, and it is standard Kimball practice. Dates never change, the key sorts correctly, and it makes fact rows readable when debugging. (Open question 3.)

### dim_date (conformed, generated)
| Column | Type | Notes |
|---|---|---|
| date_key | NUMBER(8) PK | 20170315 |
| calendar_date | DATE NOT NULL UNIQUE | |
| day_of_week_num | NUMBER(1) | ISO: Mon=1 |
| day_name | VARCHAR2(9) | 'Wednesday' (NLS-independent) |
| day_of_month | NUMBER(2) | |
| iso_week_num | NUMBER(2) | |
| month_num | NUMBER(2) | |
| month_name | VARCHAR2(9) | |
| quarter_num | NUMBER(1) | |
| year_num | NUMBER(4) | |
| year_month | VARCHAR2(7) | '2017-03' |
| month_start_date | DATE | used by trend and cohort views |
| is_weekend | CHAR(1) | 'Y'/'N' |

- **Source:** none. It is generated by `sql/ddl/08_populate_dim_date.sql`: one `MERGE` fed by `SELECT DATE '2016-01-01' + LEVEL - 1 FROM dual CONNECT BY LEVEL <= 1461`, covering 2016-01-01 to 2019-12-31 (1,461 rows). That covers every purchase (2016-09-04 to 2018-10-17) and estimated-delivery date (max 2018-11-12). Using MERGE means rerunning it adds nothing.
- **Why a table, not a function:**
  - Every report joins to the same precomputed attributes, so "what is Q3" or "what is a weekend" is defined once.
  - It can hold attributes a function can't derive, such as holidays or a fiscal calendar, later.
  - BI tools and the optimizer need a real table to join, filter and index. Calling `TO_CHAR(order_date, ...)` on 112K fact rows in every query prevents index use and repeats the logic in 12 places.
  - It is small: 1,461 rows.
- **"Conformed":** a single `dim_date` is shared by all three date roles on the fact (order date, delivered date, estimated-delivery date), and it would be reused unchanged by any future fact such as payments or reviews. With only one fact table today, the honest wording is "one conformed, role-playing date dimension". (Open question 2.)

### dim_customer (SCD Type 2)
| Column | Type | Source |
|---|---|---|
| customer_key | NUMBER(10) PK | seq_dim_customer |
| customer_unique_id | VARCHAR2(32) NOT NULL | customers.customer_unique_id (**natural key**: the person) |
| zip_code_prefix | VARCHAR2(5) | customers.customer_zip_code_prefix (LPAD to 5 with '0') |
| city | VARCHAR2(60) | customers.customer_city |
| state | VARCHAR2(2) | customers.customer_state |
| **effective_from** | DATE NOT NULL | batch start time of the load that created this version |
| **effective_to** | DATE NOT NULL | `DATE '9999-12-31'` while current; otherwise the next version's effective_from (half-open interval) |
| **is_current** | CHAR(1) NOT NULL CHECK IN ('Y','N') | |
| **version** | NUMBER(4) NOT NULL | 1, 2, 3 … |
| load_batch_id | NUMBER(10) | etl_batch.batch_id that wrote the row |

Constraints:
- `UNIQUE (customer_unique_id, version)`.
- A unique function-based index on `CASE WHEN is_current = 'Y' THEN customer_unique_id END`. The database itself then guarantees that a person has at most one current row.

Why `customer_unique_id` and not `customer_id`: in Olist, `customer_id` is generated **per order**. The same person gets a new `customer_id` on every order. `customer_unique_id` is the person, and 2,997 people have more than one order. The fact load maps `order.customer_id → customer_unique_id → current customer_key`.

**How a change is detected and closed (two statements, one transaction):**
1. Build one source row per `customer_unique_id` from staging (rule in section f).
2. **Close:** `MERGE INTO dim_customer d USING (SELECT customer_key of current rows JOIN source WHERE any tracked attribute differs) changed ON (d.customer_key = changed.customer_key) WHEN MATCHED THEN UPDATE SET is_current = 'N', effective_to = :batch_start`. The comparison uses `DECODE(d.city, s.city, 0, 1) = 1 OR ...` because `DECODE` treats two NULLs as equal and a plain `<>` does not.
   *Refined during M3:*
   - The draft matched `ON (customer_unique_id AND is_current = 'Y')`. Oracle refuses to update a column used in the MERGE `ON` clause (ORA-38104), so the MERGE matches on `customer_key` instead.
   - An intermediate `UPDATE ... WHERE EXISTS` version was correct but ran its correlated subquery about 96K times once statistics existed (over 10 minutes). The join form does it in one pass.
3. **Insert:** `INSERT` a new row (version = previous max + 1, or 1 if the person is new, is_current = 'Y', effective_from = :batch_start) for every source person who **has no current row**. After step 2 that means brand-new people plus people whose row was just closed.
4. `COMMIT` once, after both steps. If step 3 fails, step 2 rolls back too, so a person is never left with no current row.

Tracked (Type 2) attributes: zip_code_prefix, city, state. There are no Type 1 attributes on this dimension.

### dim_product (Type 1: overwrite)
| Column | Type | Source |
|---|---|---|
| product_key | NUMBER(10) PK | seq_dim_product |
| product_id | VARCHAR2(32) UNIQUE NOT NULL | products.product_id |
| category_name_pt | VARCHAR2(60) | products.product_category_name, `'sem_categoria'` if blank (610 products) |
| category_name_en | VARCHAR2(60) | translation.product_category_name_english. Falls back to the Portuguese name for the 2 categories with no translation (`pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos`), and `'unknown'` if blank |
| weight_g, length_cm, height_cm, width_cm | NUMBER | products.product_weight_g, _length_cm, _height_cm, _width_cm |
| photos_qty | NUMBER(3) | products.product_photos_qty |

### dim_seller (Type 1)
| Column | Type | Source |
|---|---|---|
| seller_key | NUMBER(10) PK | seq_dim_seller |
| seller_id | VARCHAR2(32) UNIQUE NOT NULL | sellers.seller_id |
| zip_code_prefix | VARCHAR2(5) | sellers.seller_zip_code_prefix |
| city | VARCHAR2(60) | sellers.seller_city (2 rows contain commas inside quotes, e.g. "rio de janeiro, rio de janeiro, brasil"; handled by `OPTIONALLY ENCLOSED BY '"'`) |
| state | VARCHAR2(2) | sellers.seller_state |

### dim_payment_type (Type 1)
| Column | Type | Source |
|---|---|---|
| payment_type_key | NUMBER(10) PK | seq_dim_payment_type |
| payment_type_code | VARCHAR2(20) UNIQUE NOT NULL | payments.payment_type: credit_card, boleto, voucher, debit_card, not_defined |
| payment_type_desc | VARCHAR2(40) | readable label (CASE in the load, e.g. 'Boleto (bank slip)') |

**Rule linking it to the fact grain:** a single order can be paid with several methods (e.g. voucher + card). Payments are per order, not per item. Each order gets one **primary payment type**: the method with the largest `payment_value`, with ties broken by the lowest `payment_sequential`. Every line item of that order carries that key. This is a documented simplification. (Open question 4.)

### fact_sales
| Column | Type | Source / rule |
|---|---|---|
| order_id | VARCHAR2(32) NOT NULL | order_items.order_id (degenerate dimension) |
| order_item_id | NUMBER(3) NOT NULL | order_items.order_item_id |
| order_date_key | NUMBER(8) NOT NULL FK → dim_date | orders.order_purchase_timestamp |
| delivered_date_key | NUMBER(8) **NULL** FK → dim_date | orders.order_delivered_customer_date (2,965 orders not delivered, so NULL) |
| estimated_delivery_date_key | NUMBER(8) FK → dim_date | orders.order_estimated_delivery_date |
| customer_key | NUMBER(10) NOT NULL FK → dim_customer | current version at load time, else -1 |
| product_key | NUMBER(10) NOT NULL FK → dim_product | else -1 |
| seller_key | NUMBER(10) NOT NULL FK → dim_seller | else -1 |
| payment_type_key | NUMBER(10) NOT NULL FK → dim_payment_type | primary payment type, else -1 |
| order_status | VARCHAR2(20) NOT NULL | orders.order_status (degenerate; 8 values) |
| price | NUMBER(10,2) NOT NULL | order_items.price |
| freight_value | NUMBER(10,2) NOT NULL | order_items.freight_value |
| load_batch_id | NUMBER(10) | batch that inserted or last updated the row |

Primary key: `(order_id, order_item_id)`, the natural grain. There is no fact surrogate key, because nothing references fact rows.

Indexes, planned for M2 with a comment in the DDL:
- **Bitmap** on low-cardinality foreign keys: `order_date_key` (634 distinct values), `payment_type_key` (6), `seller_key` (about 3K), `order_status` (8).
  - Bitmap indexes are compact for columns with few distinct values, and Oracle can combine several with AND/OR for star-query filters.
  - Their weakness is locking under concurrent DML. That doesn't matter here: there is one writer, the nightly batch, and many readers.
  - *Added in M3:* row-by-row bitmap maintenance is also slow for that single writer. The measured first fact load took 224 s with the bitmap indexes in place, versus 4.2 s with them UNUSABLE plus 0.24 s to rebuild. So `pkg_fact` marks them UNUSABLE before the load and REBUILDs them after it, including after a failure.
- **B-tree** on `customer_key` (about 96K distinct values, nearly unique per row) and `product_key` (about 33K). At that cardinality a bitmap has no advantage.

**Measure definition used by every view:** revenue = `SUM(price)`, the merchandise value excluding freight, over orders whose status is not `canceled` or `unavailable`. (Open question 11.)

### Non-model tables (not counted in "1 fact + 5 dims")
- 8 `ext_*` external tables and 7 `stg_*` staging tables.
- `etl_batch` and `etl_error_log`.

## e. ETL design

### Staging method: external tables (not SQL*Loader)

The `data/` folder is mounted read-only into the oracle container at `/data`. Directory objects: `RAW_DIR` → `/data/raw`, `DELTA_DIR` → `/data/delta`, `TEST_DIR` → `/data/test`, and `EXT_LOG_DIR` → `/ext_logs` (writable, for Oracle's .log and .bad files).

Why external tables:
1. The staging load becomes a plain `INSERT /*+ APPEND */ INTO stg_x SELECT ... FROM ext_x` **inside a PL/SQL package**, so the packages own the entire pipeline, including logging and batch ids.
2. There are no control files, and no client-side loader process for Bash to babysit.
3. You can `SELECT` from a file to debug it.

Trade-off: the files must be visible to the database server. That is what the mount is for.

All staging and external columns are `VARCHAR2`. Staging accepts anything; converting to NUMBER or DATE happens later, in the loads, where a failure can be logged with the row's business key.

Switching source folders (raw, test, or reprocessing) uses one guarded statement per external table: `ALTER TABLE ext_x DEFAULT DIRECTORY <dir>`, where `<dir>` must be in a hard-coded whitelist (`RAW_DIR`, `TEST_DIR`).

### Packages

| Package | Procedure | Purpose |
|---|---|---|
| **pkg_log** | `start_batch(p_feed) RETURN NUMBER` | Insert an `etl_batch` row (status RUNNING) and return its id. |
| | `log_error(p_batch_id, p_step, p_source_key, p_error_code, p_error_msg)` | Insert one `etl_error_log` row. **Autonomous transaction**. |
| | `finish_batch(p_batch_id, p_status)` | Set the end time, status and error count. Autonomous. |
| **pkg_stage** | `load_all(p_batch_id, p_source_dir)` | Point external tables at the source folder, then call each loader below. |
| | `load_orders`, `load_order_items`, `load_payments`, `load_customers`, `load_products`, `load_sellers`, `load_category_translation` | `TRUNCATE` one staging table and `INSERT /*+ APPEND */ ... SELECT` from its external table. |
| | `load_customer_delta(p_batch_id)` | Truncate `stg_customer` and load it from `ext_customer_delta` (DELTA_DIR). |
| **pkg_dim** | `load_payment_type`, `load_product`, `load_seller` | One set-based `MERGE` each (Type 1: update if changed, insert if new). |
| | `load_customer_scd2(p_batch_id, p_batch_start)` | The close-then-insert logic from section d. |
| **pkg_fact** | `load_fact_sales(p_batch_id)` | `BULK COLLECT LIMIT 10000` over staged order lines, then `FORALL ... SAVE EXCEPTIONS MERGE` into the fact. Bad rows are logged. Returns the rejected count. |
| **pkg_etl** | `run_full_load(p_source_dir DEFAULT 'RAW_DIR') RETURN NUMBER` | Orchestrator: start batch → stage → dims → fact → finish batch. Returns 0 on success, or 2 if any rows were rejected. |
| | `run_customer_delta RETURN NUMBER` | start batch → `load_customer_delta` → `load_customer_scd2` → finish batch. |

`pkg_etl` is a fifth, very small package. It exists so that batch start/finish and the step order live in one place in PL/SQL, not in a Bash heredoc.

### Load order and why
1. **Staging, all 7 tables.** Everything downstream reads staging. After this point the files are never touched again, so every later step sees one consistent snapshot.
2. **Dimensions:** `payment_type`, `product`, `seller`, `customer`. They are independent of each other. They must all finish **before** the fact, because the fact looks up their surrogate keys.
3. **Fact.**
4. `dim_date` is not part of the nightly run. It is populated once at install time and is static.

### Truncate and reload of staging
`EXECUTE IMMEDIATE 'TRUNCATE TABLE stg_x'`. TRUNCATE is DDL, so PL/SQL can only run it through dynamic SQL. It is used instead of DELETE because it:
- resets the high-water mark,
- generates almost no undo, and
- makes the reload fast.

This is followed by `INSERT /*+ APPEND */` (direct-path) and a `COMMIT`, which a direct-path insert needs before the table can be read again. Staging is disposable: it always holds exactly the latest extract.

### MERGE usage
- **Type 1 dimensions:** `MERGE INTO dim_x USING (staged, de-duplicated source) ON (natural key)`. `WHEN MATCHED THEN UPDATE ... WHERE <something changed>`, and `WHEN NOT MATCHED THEN INSERT (seq.NEXTVAL, ...)`. One statement does both jobs, and the `WHERE` avoids rewriting unchanged rows.
- **SCD2 customer:** a `MERGE` matched on `customer_key` *closes* changed current rows, followed by an `INSERT` of new versions (section d explains why it matches on the key and not on `is_current`: ORA-38104).
- **Fact:** `MERGE ON (order_id, order_item_id)`.
  - `WHEN NOT MATCHED`: insert the row.
  - `WHEN MATCHED`: update only the fields that legitimately change after an order is placed, namely `order_status`, `delivered_date_key` and `load_batch_id`. An order moves from shipped to delivered in a later extract.
  - `customer_key` is **never** updated on a match, because a fact row keeps the customer version it was loaded with.

### BULK COLLECT / FORALL: where and why
It is used only in `pkg_fact.load_fact_sales`, the one large table:
- A cursor joins staged order lines to their order, the primary payment type, and the dimension keys. It returns **raw strings**.
- `FETCH ... BULK COLLECT INTO l_rows LIMIT 10000` pulls rows in chunks of 10,000.
- **Layer 1, convert:** a PL/SQL loop over the chunk converts each line's text to typed values (NUMBER, YYYYMMDD date keys). It makes no SQL calls, so it does no engine switching. A line that can't be converted (e.g. price `abc`) is logged with its key and raw values, and skipped.
- **Layer 2, write:** `FORALL i IN 1 .. l_rows.COUNT SAVE EXCEPTIONS MERGE INTO fact_sales USING (SELECT l_rows(i).<typed fields> FROM dual) ...` writes the converted chunk. SAVE EXCEPTIONS collects database-level row errors, e.g. a delivered date outside `dim_date` violates the FK (ORA-02291).
- *Changed in M3:* the draft converted text inside the MERGE's `USING` subquery. The broken-file test showed that a conversion error there **aborts the whole FORALL statement**; SAVE EXCEPTIONS does not catch it. Converting first in PL/SQL fixed it, and the same test now logs each bad row and keeps the rest.
- **Why not a row-by-row loop:** a loop switches between the PL/SQL and SQL engines once per row (112K switches). BULK COLLECT/FORALL switches once per 10,000-row chunk.
- **Why `LIMIT`:** without it, the whole result set is held in session memory (PGA). XE is capped at 2 GB of RAM. `LIMIT` keeps memory flat however big the extract grows.
- **Why not one giant set-based MERGE,** which would be faster still: a single statement fails completely on the first bad value. The two layers let the load keep every good row and log each bad row with its key (`order_id|order_item_id`). The alternative would be Oracle's DML error logging (`LOG ERRORS INTO`). This project uses one error table, so SAVE EXCEPTIONS is used.

### Error-logging design
- `etl_batch(batch_id PK, feed_name, source_dir, started_at, finished_at, status, error_count)`, where status is RUNNING, SUCCESS, SUCCESS_WITH_ERRORS or FAILED.
- `etl_error_log(error_id PK, batch_id FK, logged_at, step_name, source_key, error_code, error_message)`, where error_message holds `DBMS_UTILITY.FORMAT_ERROR_STACK` (the full error stack, e.g. the KUP-04040 "file not found" line that SQLERRM alone drops) plus `FORMAT_ERROR_BACKTRACE` for step failures.
- **Autonomous transaction:** `pkg_log.log_error` and `finish_batch` use `PRAGMA AUTONOMOUS_TRANSACTION` and commit on their own. When a step fails, its work is rolled back, but the error record, which was written in its own transaction, **survives the rollback**. Without the pragma, the rollback would erase the evidence of what failed.
- **Two kinds of error:**
  1. **Row-level** (the fact load): either a conversion error caught in layer 1, or ORA-24381 from SAVE EXCEPTIONS in layer 2 (the load loops over `SQL%BULK_EXCEPTIONS`). Each failed row is logged and the load continues. The batch ends `SUCCESS_WITH_ERRORS` and the wrapper exits 2.
  2. **Step-level** (anything else, e.g. a missing file or a failed dimension MERGE): each procedure's `WHEN OTHERS` handler calls `log_error`, runs `ROLLBACK`, then `RAISE`. `pkg_etl` catches it, sets the batch to FAILED and re-raises. sqlplus `WHENEVER SQLERROR EXIT FAILURE` makes the wrapper exit 1.
- Row counts per step are printed with `DBMS_OUTPUT` and end up in the wrapper's log file.

### Commit strategy and a load dying halfway
There is **one commit per step**: after each staging table, after each dimension, and after the whole fact load.

If the load dies during the fact step:
- the fact changes since the last commit roll back (nothing half-written),
- staging and dimensions stay committed, which is harmless because they are complete and idempotent,
- the batch row says FAILED and `etl_error_log` says where and why,
- the wrapper exits 1 and releases the lock.

Recovery is simply **re-running the load**. Idempotency (below) guarantees no duplicates.

*Added in M5:* if the process is **killed** (e.g. the container stops) it never reaches its exception handler, so its batch would stay `RUNNING` forever. Before every load, while holding the lock (so no other load can really be running), `bin/nightly_load.sh` calls `pkg_log.fail_abandoned_batches`. That procedure marks any leftover `RUNNING` batch as FAILED and adds an error row saying why. The wrapper's exit codes are 0 success, 1 failed, 2 rows rejected, 3 skipped because another load holds the lock, and 4 bad arguments.

The fact commits once at the end, not once per 10,000-row chunk. At 112K rows the undo cost is small, and "all or nothing" is easier to reason about. (Commit-per-chunk would also be safe here because of MERGE, and is the choice for much larger volumes.)

### Idempotency: rerunning the load must not duplicate rows
| Layer | Why a rerun changes nothing |
|---|---|
| staging | truncated and reloaded, not appended |
| Type 1 dims | MERGE on natural key; `WHEN MATCHED ... WHERE changed` does nothing when unchanged |
| dim_customer | a new version is created only when a tracked attribute actually differs from the current row |
| fact | MERGE on `(order_id, order_item_id)`, which is also the primary key, so a duplicate is impossible even with a bug |
| dim_date | MERGE on date_key |

## f. SCD2 demonstration plan

**The request assumed Olist customers never change. The data shows otherwise.** Because `customer_id` is per order, the customers file is really a flattened history. **252 people** have more than one distinct (zip, city, state) across their orders, and **122** of those differ in city or state. These are real address changes, but the file has no change dates.

**Proposed plan (uses only real rows, with no modified values at all):**
1. **Initial (full) load rule:** each person's dimension row takes the address on their **earliest order** (by `order_purchase_timestamp`).
2. **Delta extract `data/delta/customer_delta.csv`:** one row per person whose address on their **latest order** differs from their earliest-order address. The row is copied **verbatim** from `olist_customers_dataset.csv`: it is the customer row belonging to that latest order. Measured in M6: **249 people** (39 changed state, 82 changed city within the same state, 128 changed only the zip prefix). All 249 rows appear verbatim in the raw file. The other 3 of the 252 people with several addresses ended up back at their first address (A → B → A), so they have no change.
3. **Generator `bin/make_delta.sh`:** runs `sql/delta/make_customer_delta.sql` against the staged raw data (a `ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_ts)` query) and spools the CSV with sqlplus. The output depends only on the raw files, so it is deterministic: the same input always gives a byte-identical file. The file is small, so it is committed.
4. **`bin/nightly_load.sh --delta`** runs `pkg_etl.run_customer_delta`. The expected result for each affected person:
   - v1 closed (`is_current='N'`, `effective_to` = batch start),
   - v2 current with the new city or state,
   - every other person untouched,
   - total current rows still 96,096.
   A second delta run changes nothing.

Honest limitations:
- **Facts keep the version they were loaded with.** Orders placed after a move, loaded in the initial load, point to v1. Re-keying history would need effective dates from order dates (a "historical backfill"). That is out of scope.
- **A later full load replays the raw extract.** Its earliest-address rule would record the 252 customers "moving back" as v3. That is correct SCD2 behaviour for what the source says, but it means the tests run the delta last, and the cron job should not be left running after a demo unless you accept that.

**Fallback, option A,** if you prefer your original wording: pick every 500th customer (ordered by `customer_unique_id`, about 192 people). Move each to the most common real customer city (São Paulo/SP with its most common zip prefix), or to the most common Rio de Janeiro/RJ city and zip if they already live in SP. Every value would still be real, but it would be assigned by a rule. (Open question 5.)

## g. The 12 report views

Common filter: `order_status NOT IN ('canceled','unavailable')`. Revenue means `SUM(price)`.

| # | View | Business question | SQL features |
|---|---|---|---|
| 1 | v_rpt_monthly_revenue | How is revenue trending month by month, how does each month compare to the previous one, and what is the running total for the year? | CTE, LAG, SUM() OVER (running YTD) |
| 2 | v_rpt_revenue_state_category | Which customer states and product categories drive revenue, with state subtotals and a grand total? | ROLLUP, GROUPING() |
| 3 | v_rpt_payment_mix_monthly | How does the share of credit card, boleto, voucher and debit card revenue shift month by month? | CTE, PIVOT |
| 4 | v_rpt_top_categories_by_state | What are the top 3 product categories by revenue in each customer state? | CTE, RANK() |
| 5 | v_rpt_seller_rank_in_state | Who are the 10 leading sellers in each seller state, and what share of that state's revenue does each hold? | CTE, RANK(), SUM() OVER (PARTITION BY) ratio |
| 6 | v_rpt_cohort_retention | Of the customers who first bought in month X, what percentage bought again 1, 2, 3 … months later? | CTEs, MIN() OVER, CONNECT BY row generator (fills 0% months) |
| 7 | v_rpt_late_delivery_cube | What share of delivered orders arrived after the estimated date, by customer state and year, with every subtotal? | CTE, CUBE, GROUPING_ID() |
| 8 | v_rpt_category_quarter_pivot | How does each category's revenue compare across the quarters of 2017 and 2018? | CTE, PIVOT |
| 9 | v_rpt_repeat_purchase_gap | For customers who ordered more than once, how many days pass between one order and the next? | CTEs, ROW_NUMBER(), LAG(), LEAD(), COUNT() OVER |
| 10 | v_rpt_revenue_grouping_sets | What is revenue by year, by payment type, and in total, all in one result set? | GROUPING SETS, GROUPING_ID() |
| 11 | v_rpt_weekday_orders_pivot | Which weekday gets the most orders, and did that change between 2017 and 2018? | CTE, PIVOT |
| 12 | v_rpt_customer_moves | Which customers changed address, from where to where, and when did the warehouse record it? (SCD2) | CTE, LAG() OVER (PARTITION BY customer ORDER BY version) |

Coverage, where the requirement is at least 2 each:
- **Window functions:** 1, 4, 5, 6, 9, 12 (6 views)
- **CTEs:** 1, 3, 4, 5, 6, 7, 8, 9, 11, 12 (10 views)
- **ROLLUP/CUBE/GROUPING SETS:** 2, 7, 10 (3 views)
- **PIVOT:** 3, 8, 11 (3 views)

Each view file starts with a comment holding its business question, and the same text is stored with `COMMENT ON TABLE v_rpt_x IS '...'`, so it is visible in `USER_TAB_COMMENTS`.

View 12 returns rows only after the delta load. The test runs it after the delta.

## h. Tableau plan

Tableau **Public** can only connect to files (and a few cloud sources), not to Oracle. So `bin/export_tableau.sh` spools views to CSV with sqlplus `SET MARKUP CSV ON`. These CSVs are the data sources. They are small, so they are committed, which lets anyone rebuild the dashboards.

**Dashboard 1: Revenue Trend.** Source `tableau/revenue_trend.csv` ← `v_rpt_monthly_revenue`.

| Field | Type | Use |
|---|---|---|
| month_start | date | x-axis |
| year_num | integer | filter / colour |
| order_count | integer | bar |
| revenue | decimal | line |
| avg_order_value | decimal | KPI tile |
| prev_month_revenue | decimal | tooltip |
| mom_growth_pct | decimal | bar (MoM growth) |
| ytd_revenue | decimal | running-total line |

**Dashboard 2: Customer Cohort Retention.** Source `tableau/cohort_retention.csv` ← `v_rpt_cohort_retention`.

| Field | Type | Use |
|---|---|---|
| cohort_month | date | rows of the heatmap |
| months_since_first | integer (0…N) | columns of the heatmap |
| cohort_size | integer | bar chart / tooltip |
| active_customers | integer | tooltip |
| retention_pct | decimal | heatmap colour, average-retention line |

`tableau/GUIDE.md` (M8) will give numbered click-by-click steps: connect to text file, set types, build each sheet, assemble the dashboard, publish to Tableau Public.

## i. Testing plan

`tests/run_all.sh` runs inside `tools` and prints `PASS`/`FAIL` per assertion. It exits non-zero if any assertion fails. Starting point: `bin/install.sh --reset` (which runs `sql/reset_schema.sql`) drops every object in the DW schema and rebuilds it (a clean database without recreating the container).

| Area | How it is verified |
|---|---|
| **Schema** | Query the data dictionary: exactly 1 `FACT_%` and 5 `DIM_%` tables; each has a PK; the fact has 7 FKs (3 date roles + 4 dimensions); the 4 bitmap indexes exist (`USER_INDEXES.index_type='BITMAP'`); `dim_date` has 1,461 rows; each dimension has its -1 row. |
| **Full load counts** | After the first `nightly_load.sh`: fact = 112,650; current customers = 96,096; products = 32,951; sellers = 3,095; payment types = 5 (+ unknown); `SUM(price)` matches the CSV total 13,591,643.70; error log empty; exit code 0. |
| **Idempotency** | Run the full load again. Every table's count and `SUM(price)` are identical, and `dim_customer` still has only version-1 rows. |
| **Error logging, row-level** | The test copies `data/raw` into `data/test` and uses `sed` to corrupt the price on 3 known lines of `order_items` (e.g. `abc`). Run `--source TEST_DIR`: exit code 2, batch status `SUCCESS_WITH_ERRORS`, exactly 3 `etl_error_log` rows with those 3 `order_id|item_id` keys, fact count unchanged. |
| **Error logging, step-level** | Remove the customers file from `data/test` and run again: exit code 1, batch `FAILED`, one error row naming the staging step (KUP-04040 file not found). |
| **Lock file** | (a) Start `sleep 60 &` and write its PID into `logs/nightly.lock`. The wrapper must exit 3 ("already running") without touching the DB. (b) Write a dead PID (e.g. 999999) into the lock. The wrapper must log "stale lock removed", run, and exit 0. |
| **Log rotation** | Create 20 dummy `nightly_*.log` files with old timestamps (`touch -d`). After one run exactly 14 remain, and the newest is the real one. |
| **SCD2** | `make_delta.sh`, then `nightly_load.sh --delta`. For every person in the delta file: one v1 row with `is_current='N'` whose `effective_to` equals the v2 row's `effective_from`, and one v2 row that is current with the new city/state. No person has 2 current rows. Current count is still 96,096. Rerun the delta: nothing changes. |
| **Views** | For each of the 12 `v_rpt_*` views, `SELECT COUNT(*)` > 0. The test also checks that exactly 12 exist. |
| **Tableau export** | Both CSVs exist, have a header row, and have more than 1 data row. |

## j. Proposed repository tree

```
retail/                         (you can name the GitHub repo retail-warehouse)
├── .env.example                committed; .env is gitignored
├── .gitignore                  .env, data/raw/, data/test/, logs/
├── .gitattributes              *.sh *.sql *.cron Dockerfile → eol=lf (Windows checkout must not add CR)
├── docker-compose.yml
├── DESIGN.md  README.md
├── docker/
│   ├── tools/Dockerfile        debian:bookworm-slim + Instant Client (basic-lite + sqlplus) + cron
│   └── oracle/init/01_create_dw_user.sql
├── bin/
│   ├── up.sh  down.sh          host: start/stop + wait until DW user can log in
│   ├── sql.sh                  helper: run a .sql file as DW via sqlplus (password via env, not argv)
│   ├── install.sh              run sql/install.sql (DDL, date dim, packages, views)
│   ├── nightly_load.sh         the wrapper (--delta, --source DIR)
│   ├── make_delta.sh
│   └── export_tableau.sh
├── cron/nightly.cron
├── sql/
│   ├── install.sql  reset_schema.sql
│   ├── ddl/  01_etl_tables.sql 02_directories_and_external_tables.sql 03_staging_tables.sql
│   │         04_sequences.sql 05_dimensions.sql 06_fact.sql 07_indexes.sql 08_populate_dim_date.sql
│   ├── packages/ pkg_log.pks/.pkb pkg_stage.pks/.pkb pkg_dim.pks/.pkb pkg_fact.pks/.pkb pkg_etl.pks/.pkb
│   ├── views/  01_v_rpt_monthly_revenue.sql … 12_v_rpt_customer_moves.sql
│   ├── delta/make_customer_delta.sql
│   └── export/revenue_trend.sql cohort_retention.sql
├── data/
│   ├── raw/                    Olist CSVs (gitignored: 126 MB, Kaggle CC BY-NC-SA licence; README says how to get them)
│   ├── delta/customer_delta.csv   generated, committed
│   └── test/                   generated by tests, gitignored
├── logs/                       gitignored (nightly/, ext_logs/, nightly.lock)
├── tableau/ revenue_trend.csv cohort_retention.csv GUIDE.md
└── tests/ run_all.sh  sql/assert_*.sql
```

## k. Milestones and checkpoints

Each milestone ends with a commit (plain message, no attribution trailers). **I stop and show you the output, and wait for your go-ahead before starting the next one.**

| M | Deliverable | What I show you at the checkpoint |
|---|---|---|
| M1 | compose file, tools Dockerfile, DW user init, `.env.example`, `bin/up.sh` | `./bin/up.sh` output ending in "DW user connected"; `docker compose ps` healthy; `SELECT user FROM dual` → DW |
| M2 | all DDL, indexes (with bitmap rationale comment), date dim generator, `install.sh` | install log; `USER_TABLES`/`USER_INDEXES` listing; `dim_date` count 1,461 |
| M3 | 5 packages | compile with zero errors (`USER_ERRORS` empty); one manual `run_full_load` with row counts per step |
| M4 | 12 views | each view's row count and first 3 rows |
| M5 | `nightly_load.sh`, `nightly.cron`, cron running in tools | a real run's log file; the lock demo (exit 3); `crontab -l` inside tools |
| M6 | delta generator + SCD2 run | delta row count; before/after `dim_customer` rows for 2–3 real people |
| M7 | `tests/run_all.sh` | full PASS/FAIL output from a clean schema |
| M8 | two CSV exports + `tableau/GUIDE.md` | CSV heads; the guide |
| M9 | README.md | rendered README |

## l. Risks and open questions

**Questions that need your decision:**
1. **"100K+ orders" is false.** The file has **99,441 orders**. True alternatives:
   - "~100K orders / 112K order line items"
   - "112K+ order line items"
   - "100K+ fact rows"

   Which wording do you want in the README? I will not write "100K+ orders".
2. **"Conformed date dimension"** with one fact table: the accurate wording is "one conformed, role-playing date dimension (order, delivered, estimated dates)". Is that OK?
3. **dim_date key = YYYYMMDD,** not a sequence. This is standard, but it is technically a "smart key". OK?
4. **5th dimension = payment type,** using the "primary payment type per order" rule. The alternative is `dim_order_status`, which is simpler but makes weaker reports. Which do you want?
5. **SCD2 delta:** real address changes found in the data (my recommendation, section f), or rule-based moves of every 500th customer (option A)?
6. **Retention will look very low.** Only about 3% of Olist customers ever order twice, so the cohort heatmap will be mostly near 0%. That is a real finding (a marketplace with low repeat purchasing) and a good talking point, but the chart will not look "healthy". OK?
7. **Sparse edge months:** 2016-09 to 2016-12 and 2018-09 to 2018-10 have very few orders. The view keeps them. The Tableau guide filters to 2017-01 to 2018-08. OK?
8. **Oracle image:** `gvenzl/oracle-xe:21-slim` (community, about 1 GB, fast) versus Oracle's official `container-registry.oracle.com/database/express:21.3.0-xe` (larger, slow first start). I recommend gvenzl.
9. **Revenue definition:** `SUM(price)` excluding freight, and excluding canceled or unavailable orders. OK?

**Technical risks (handled in the build):**
- **Line endings (resolved in M2).** Measured by counting carriage-return bytes: 6 of the 7 loaded CSVs use Unix LF (`RECORDS DELIMITED BY NEWLINE`); only `product_category_name_translation.csv` uses CRLF (`RECORDS DELIMITED BY 0x'0D0A'`). An earlier discovery check reported CRLF everywhere; that check was wrong (the Git Bash grep pattern for a carriage return matched every line).
- **Git Bash path mangling.** Git Bash rewrites `/work/...` arguments passed to `docker compose exec`. `bin/*.sh` sets `MSYS_NO_PATHCONV=1`.
- **CRLF in scripts.** `.gitattributes` forces LF for scripts, or Bash in the container breaks with `$'\r': command not found`.
- **Instant Client download.** The Dockerfile downloads from Oracle's public, no-login URL at a pinned version. If Oracle moves the file, the build fails loudly and the pin needs updating.
- **Bind-mount speed.** Reading about 60 MB of CSV from a Windows folder into a container is slower than a native disk. I expect a full load in minutes, not seconds, and will report the real time.
- **XE limits.** 2 CPU threads, 2 GB RAM and 12 GB of user data are far above what this needs.
- **Redo log size (resolved in M3).** The gvenzl slim image ships two 10 MB redo logs, and the first full load spent about 380 s waiting on `log file switch (checkpoint incomplete)`. `docker/oracle/init/02_resize_redo_logs.sh` replaces them with 3 x 200 MB on first start.
- **PID reuse in the lock check.** A stale lock whose PID was reused by an unrelated process would be treated as live, and the run would be skipped, not duplicated. That is the safe direction, and it is documented.
- **cron only while Docker runs.** See section c.

### Decisions (approved 2026-09-26)
1. Wording: "~100K orders (112K+ order line items)". "100K+ orders" is never used.
2. "One conformed, role-playing date dimension."
3. `dim_date.date_key` = YYYYMMDD.
4. Fifth dimension = `dim_payment_type`, using the primary-payment-type rule.
5. SCD2 delta = real address changes (earliest-order address in the full load, latest-order row in the delta).
6. Low retention is shown as-is and explained.
7. Tableau guide filters to 2017-01 through 2018-08. The views keep all months.
8. Oracle image `gvenzl/oracle-xe:21-slim`.
9. Revenue = `SUM(price)`, excluding freight and excluding canceled/unavailable orders.
