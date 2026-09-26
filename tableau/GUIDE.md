# Building the two Tableau Public dashboards

You will build one Tableau Public workbook with two dashboards:

| Dashboard | Data source file | Exported from warehouse view |
|---|---|---|
| 1. Revenue Trend | `tableau/revenue_trend.csv` (one row per month) | `v_rpt_monthly_revenue` |
| 2. Customer Cohort Retention | `tableau/cohort_retention.csv` (one row per cohort × month offset) | `v_rpt_cohort_retention` |

Tableau Public (the free edition) can only read files, not an Oracle database. That is why the warehouse views are exported to CSV. The export uses the same numbers the views return, and `tests/run_all.sh` checks that the CSV totals equal the warehouse totals.

Menu names are from Tableau Public Desktop 2024/2025 and may differ slightly in other versions. Each step says *what* to achieve, so you can find the equivalent control if a label has moved.

---

## Part A: Preparation

1. Install **Tableau Public** (desktop app, free) from <https://public.tableau.com/app/discover> → *Create* → *Download the app*. Create a free Tableau Public account; you need it to save your work.
2. Make sure the CSVs are current. After any load, run:
   ```bash
   docker compose exec tools bin/export_tableau.sh
   ```
   Expected output: `tableau/revenue_trend.csv: 25 rows` and `tableau/cohort_retention.csv: 301 rows`.
3. **Date range used on both dashboards: January 2017 to August 2018.** The data starts in September 2016 and ends in October 2018, but those edge months are almost empty (Nov 2016 has 0 orders, Dec 2016 has 1, Sep 2018 has 1). Left in, they create meaningless spikes: January 2017's month-over-month growth is **+1,101,719 %** because December 2016 earned R$ 10.90. The views keep every month; the dashboards filter them.

---

## Part B: Dashboard 1, Revenue Trend

### Connect
4. Open Tableau Public. In the **Connect** pane choose **Text file** and open `tableau/revenue_trend.csv`.
5. On the **Data Source** page, check each column's type (the small icon above the column name; click it to change):
   - `month_start` → **Date**
   - `year_num`, `month_num`, `order_count` → **Number (whole)**
   - `revenue`, `avg_order_value`, `prev_month_revenue`, `mom_growth_pct`, `ytd_revenue` → **Number (decimal)**

   Empty cells (e.g. `prev_month_revenue` in the first month) are normal: there is no previous month.
6. Rename the data source (top-left, double-click the name) to **Revenue Trend**.
7. Add a **data source filter** so every sheet uses the same range: top-right of the Data Source page → **Filters: Add…** → **Add…** → `month_start` → **Range of dates** → start `2017-01-01`, end `2018-08-31` → OK.
8. Click **Sheet 1** at the bottom.
9. In the Data pane, right-click `year_num` → **Convert to Dimension**, then right-click again → **Convert to Discrete**. Do the same for `month_num`. They are labels, not quantities to add up.

### Sheet 1: "Revenue by month" (line chart)
10. Rename the sheet (double-click its tab) to **Revenue by month**.
11. Drag `month_start` to **Columns**. Right-click the pill → choose the **second** "Month" option (the one showing *May 2015*; this is a continuous month, and the pill turns green).
12. Drag `revenue` to **Rows** (it shows as `SUM(revenue)`; there is one row per month, so the sum is that month's revenue).
13. On the **Marks** card, set the mark type to **Line**.
14. Format the axis as money: right-click the revenue axis → **Format…** → Numbers → **Currency (Custom)**, prefix `R$ `, 0 decimals.

### Sheet 2: "Month-over-month growth" (bar chart)
15. New sheet (the icon next to the sheet tabs), rename it **Month-over-month growth**.
16. Drag `month_start` to **Columns**, again as the continuous **Month** (step 11).
17. Drag `mom_growth_pct` to **Rows**. Mark type: **Bar**.
18. Drag `month_start` to **Filters** → Range of dates → start `2017-02-01`. January 2017 is compared with the almost empty December 2016 (step 3) and would flatten every other bar.
19. **Analysis → Create Calculated Field…**, name `Growth direction`, formula:
    ```
    IF SUM([mom_growth_pct]) >= 0 THEN "Up" ELSE "Down" END
    ```
    Drag `Growth direction` to **Color**.

### Sheet 3: "Year-to-date revenue, 2017 vs 2018" (lines per year)
20. New sheet, rename it **YTD revenue by year**.
21. Drag `month_num` (discrete, from step 9) to **Columns** and `ytd_revenue` to **Rows**.
22. Drag `year_num` (discrete) to **Color**. Mark type: **Line**. You get one cumulative line per year, so you can compare 2018 against 2017 month by month.

### Sheet 4: "KPIs" (three headline numbers)
23. New sheet, rename it **KPIs**.
24. Create a calculated field `Average order value`:
    ```
    SUM([revenue]) / SUM([order_count])
    ```
    **Why not AVG(avg_order_value)?** Averaging the monthly averages gives a quiet month (a few hundred orders) the same weight as a busy one (7,000+ orders). Total revenue ÷ total orders is the correct overall figure.
25. Double-click `revenue`, then `order_count`, then `Average order value`. Tableau builds a table using **Measure Names / Measure Values**. Click **Swap Rows and Columns** in the toolbar so the three numbers sit side by side; set mark type **Text** and increase the font size (Marks → Text → `…`).
26. Format `revenue` and `Average order value` as `R$` currency (step 14), `order_count` as a whole number with a thousands separator.

### Assemble the dashboard
27. **Dashboard → New Dashboard**. In the left pane set **Size** → *Fixed size* → 1200 × 800 (or *Automatic*).
28. Drag the sheets onto the canvas: **KPIs** across the top, **Revenue by month** below it (full width), and **Month-over-month growth** and **YTD revenue by year** side by side at the bottom.
29. Tick **Show dashboard title** and set it to *Olist Revenue Trend, January 2017 – August 2018*.
30. From **Objects**, drag a **Text** box to the bottom and write:
    *Revenue = item price, excluding freight; canceled and unavailable orders excluded. Source: Oracle 21c warehouse, view v_rpt_monthly_revenue. Data: Olist Brazilian E-Commerce (Kaggle, CC BY-NC-SA 4.0).*
31. Rename the dashboard tab to **Revenue Trend**.

### Check your numbers (Jan 2017 – Aug 2018)
| What | Expected value |
|---|---|
| Total revenue (KPI) | **R$ 13,449,529.68** |
| Orders (KPI) | **97,905** |
| Average order value (KPI) | **R$ 137.37** |
| Highest month | **November 2017**, R$ 1,003,862.14 (Black Friday), MoM +52.1 % |
| YTD at Dec 2017 / Aug 2018 | R$ 6,108,492.27 / R$ 7,341,037.41 |

If a KPI differs, the usual cause is a missing data source filter (step 7) or AVG instead of SUM.

---

## Part C: Dashboard 2, Customer Cohort Retention

**How to read it:** a *cohort* is the group of customers whose first purchase was in the same month. For each cohort, the chart shows what percentage bought again 1, 2, 3 … months after that first month. A customer is a person (`customer_unique_id`), so someone who moved address (SCD2 version 2) is still one customer.

### Connect
32. **Data → New Data Source → Text file** → `tableau/cohort_retention.csv`.
33. Check the column types:
    - `cohort_month` → **Date**
    - `months_since_first`, `cohort_size`, `active_customers` → **Number (whole)**
    - `retention_pct` → **Number (decimal)**
34. Rename the data source to **Cohort Retention**.
35. Add a data source filter (step 7): `cohort_month` from `2017-01-01` to `2018-08-01`.
36. Go to a new sheet. Right-click `months_since_first` → **Convert to Dimension**.
37. Create a calculated field `Retention rate`:
    ```
    SUM([active_customers]) / SUM([cohort_size])
    ```
    Right-click it in the Data pane → **Default Properties → Number Format → Percentage**, 2 decimals.
    **Why this and not AVG(retention_pct)?** When several cohorts are combined (e.g. the average curve in sheet 2), a cohort of 750 people and a cohort of 7,000 should not count equally. Dividing the totals weights every *customer* equally. For a single cell of the heatmap both give the same number.

### Sheet 1: "Retention heatmap"
38. Rename the sheet **Retention heatmap**.
39. Drag `cohort_month` to **Rows**. Right-click the pill → choose the **second** "Month" option (*May 2015*), then right-click again → **Discrete**. Each row is now one cohort, labelled like *January 2017*.
40. Drag `months_since_first` to **Columns** (discrete, blue).
41. Drag `months_since_first` to **Filters** → select all **except 0**. Month 0 is always 100 % (it is the first purchase itself), and leaving it in would make every other cell look the same pale colour.
42. Drag `Retention rate` to **Color** and to **Label**. Mark type: **Square**.
43. Click **Color → Edit Colors…** → pick a sequential palette (e.g. *Blue*). The cells are small numbers (mostly under 1 %), so the palette spreads them out; that is expected.

### Sheet 2: "Average retention curve"
44. New sheet, rename it **Average retention curve**.
45. Drag `months_since_first` to **Columns**, then right-click the pill → **Continuous** (green).
46. Drag `Retention rate` to **Rows**. Mark type: **Line**; on **Color** tick *Markers: show all*.
47. Filter `months_since_first` to **1 to 12**. Later offsets exist only for the oldest cohorts, so the curve would rest on very few customers.

### Sheet 3: "Cohort size"
48. New sheet, rename it **Cohort size**.
49. Drag `cohort_month` to **Rows** as in step 39 (discrete Month/Year).
50. Drag `cohort_size` to **Columns**, then right-click the pill → **Measure → Minimum**. Each cohort's size is repeated on every one of its rows, so SUM would multiply it; MIN (or AVG) returns the size once. Mark type: **Bar**.

### Assemble the dashboard
51. **Dashboard → New Dashboard**, same size as dashboard 1.
52. Place **Retention heatmap** on the left (most of the width) and **Cohort size** on the right, so its bars line up with the heatmap rows. Put **Average retention curve** along the bottom.
53. Title: *Olist Customer Cohort Retention, first purchases January 2017 – August 2018*.
54. Text box:
    *Month-1 retention is about 0.45 %: almost every Olist customer buys only once (about 3 % of customers ever order twice). That is a genuine property of this marketplace data, not a loading error. Customer = person (customer_unique_id), stable across SCD2 address changes. Source: Oracle 21c warehouse, view v_rpt_cohort_retention.*
55. Rename the dashboard tab to **Cohort Retention**.

### Check your numbers
| What | Expected value |
|---|---|
| Customers in cohorts Jan 2017 – Aug 2018 (sum of Cohort size) | **94,693** |
| January 2017 cohort | size **752**; month 1: **3** customers = **0.40 %** |
| Average curve, month 1 / 2 / 3 | **0.45 % / 0.31 % / 0.24 %** |

---

## Part D: Publish and take screenshots

56. **File → Save to Tableau Public As…**, sign in, name the workbook *Olist Retail Warehouse*. Tableau uploads it and opens it in your browser; both dashboards are tabs of this one workbook. Copy the URL for your README.
    Note: everything saved to Tableau Public is **public**. The Olist data is already public (Kaggle), so that is fine, but never publish private data this way.
57. For the README screenshots: open each dashboard → **Dashboard → Export Image…** → save as
    - `docs/screenshots/revenue_trend.png`
    - `docs/screenshots/cohort_retention.png`

## Part E: After new data is loaded

58. Run the load (`bin/nightly_load.sh`), then `bin/export_tableau.sh`.
59. In Tableau: **Data → Revenue Trend → Refresh**, then **Data → Cohort Retention → Refresh**.
60. **File → Save to Tableau Public** to republish.
