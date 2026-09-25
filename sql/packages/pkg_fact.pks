CREATE OR REPLACE PACKAGE pkg_fact AS
/*
    pkg_fact: loads fact_sales (grain: one row per order line item).

    What it does
      1. A cursor joins each staged order line to its order, its customer, its
         product, its seller and its order's primary payment type, and looks up
         each dimension's surrogate key (or -1 "Unknown" if none is found).
         The cursor returns the raw text values from staging.
      2. BULK COLLECT fetches 10,000 lines at a time (LIMIT).
      3. Each line of the chunk is converted from text to typed values in
         PL/SQL (no SQL involved, so no engine switching). A line with a value
         that cannot be converted (e.g. price 'abc') is logged and skipped.
      4. FORALL ... SAVE EXCEPTIONS runs one MERGE per converted line for the
         whole chunk in a single call to the SQL engine:
         - new line      -> inserted
         - existing line -> order_status / delivered date updated if changed
         SAVE EXCEPTIONS collects database-level row errors (e.g. a foreign
         key violation) instead of stopping at the first one.
         Every rejected row (step 3 or 4) is written to ETL_ERROR_LOG with its
         key (order_id|order_item_id); all good rows are kept.
      5. One COMMIT at the end: the fact step is all-or-nothing.
      6. The fact's bitmap indexes are set UNUSABLE before step 2 and rebuilt
         after step 5 (also after a failure). See set_bitmap_indexes in the body.

    Why it exists / why this technique
      - Row-by-row (a cursor FOR loop with one MERGE per iteration) switches
        between the PL/SQL and SQL engines 112K times. FORALL switches once per
        10,000-row chunk.
      - LIMIT keeps memory flat: without it BULK COLLECT would pull every row
        into session memory at once.
      - One big set-based MERGE would be even faster, but a single bad value
        would fail the whole statement. SAVE EXCEPTIONS lets the load keep the
        good rows and report each bad one individually.
      - MERGE on the primary key (order_id, order_item_id) makes re-runs safe:
        a line that is already loaded is never inserted twice.

    Primary payment type: an order may be paid with several methods. Each
    order gets the method with the largest payment_value (ties: lowest
    payment_sequential), and every line of the order carries that key.
*/

    -- p_rejected returns how many rows failed and were logged.
    PROCEDURE load_fact_sales (
        p_batch_id  IN  NUMBER,
        p_rejected  OUT NUMBER
    );

END pkg_fact;
/
