-- =============================================================================
-- install_views.sql
-- Creates the 12 reporting views. CREATE OR REPLACE makes this safe to re-run
-- on its own after editing a view:
--   bin/sql.sh sql/views/install_views.sql
-- =============================================================================
PROMPT   v_rpt_monthly_revenue
@sql/views/01_v_rpt_monthly_revenue.sql
PROMPT   v_rpt_revenue_state_category
@sql/views/02_v_rpt_revenue_state_category.sql
PROMPT   v_rpt_payment_mix_monthly
@sql/views/03_v_rpt_payment_mix_monthly.sql
PROMPT   v_rpt_top_categories_by_state
@sql/views/04_v_rpt_top_categories_by_state.sql
PROMPT   v_rpt_seller_rank_in_state
@sql/views/05_v_rpt_seller_rank_in_state.sql
PROMPT   v_rpt_cohort_retention
@sql/views/06_v_rpt_cohort_retention.sql
PROMPT   v_rpt_late_delivery_cube
@sql/views/07_v_rpt_late_delivery_cube.sql
PROMPT   v_rpt_category_quarter_pivot
@sql/views/08_v_rpt_category_quarter_pivot.sql
PROMPT   v_rpt_repeat_purchase_gap
@sql/views/09_v_rpt_repeat_purchase_gap.sql
PROMPT   v_rpt_revenue_grouping_sets
@sql/views/10_v_rpt_revenue_grouping_sets.sql
PROMPT   v_rpt_weekday_orders_pivot
@sql/views/11_v_rpt_weekday_orders_pivot.sql
PROMPT   v_rpt_customer_moves
@sql/views/12_v_rpt_customer_moves.sql
PROMPT   v_ref_natural_keys (key lists for pre-load checks)
@sql/views/ref_natural_keys.sql
PROMPT   grants for the reporting role
@sql/views/grant_report_access.sql
