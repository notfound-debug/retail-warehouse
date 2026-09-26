-- =============================================================================
-- v_rpt_customer_moves
-- Business question: Which customers changed address, from where to where,
--                    and when did the warehouse record the change?
-- SQL features:      CTE, LAG() OVER (PARTITION BY ... ORDER BY version)
-- One row per:       address change, i.e. every SCD2 version after the first.
--
-- Reads the SCD2 history in dim_customer. LAG returns the previous version's
-- address for the same person, so each new version is shown next to the
-- address it replaced. Returns no rows until a customer delta has been loaded
-- (after the initial load every customer has only version 1).
-- =============================================================================
CREATE OR REPLACE VIEW v_rpt_customer_moves AS
WITH versions AS (
    SELECT customer_unique_id,
           version,
           LAG(city)            OVER (PARTITION BY customer_unique_id ORDER BY version) AS from_city,
           LAG(state)           OVER (PARTITION BY customer_unique_id ORDER BY version) AS from_state,
           LAG(zip_code_prefix) OVER (PARTITION BY customer_unique_id ORDER BY version) AS from_zip_prefix,
           city            AS to_city,
           state           AS to_state,
           zip_code_prefix AS to_zip_prefix,
           effective_from  AS recorded_at,
           is_current
    FROM   dim_customer
    WHERE  customer_key <> -1
)
SELECT customer_unique_id,
       version,
       from_city,
       from_state,
       from_zip_prefix,
       to_city,
       to_state,
       to_zip_prefix,
       CASE WHEN from_state <> to_state THEN 'Y' ELSE 'N' END AS changed_state,
       recorded_at,
       is_current
FROM   versions
WHERE  version > 1;

COMMENT ON TABLE v_rpt_customer_moves IS 'Which customers changed address, from where to where, and when did the warehouse record the change?';
