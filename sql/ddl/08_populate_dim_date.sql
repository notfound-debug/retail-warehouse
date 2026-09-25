-- =============================================================================
-- 08_populate_dim_date.sql
-- Date dimension generator: one row per day from 2016-01-01 to 2019-12-31
-- (1,461 days). This covers every Olist purchase date (2016-09-04 .. 2018-10-17)
-- and estimated delivery date (latest 2018-11-12).
--
-- How it works: CONNECT BY LEVEL <= n against DUAL is the classic Oracle way to
-- produce n rows; adding LEVEL - 1 to the start date turns them into n dates.
--
-- MERGE (not INSERT) makes the script safe to run again: existing days are
-- left alone and only missing days are added. To extend the calendar, change
-- the end date and re-run.
--
-- Names use 'NLS_DATE_LANGUAGE=ENGLISH' and the ISO week, so the result does not
-- depend on the session's language or territory settings.
-- =============================================================================

MERGE INTO dim_date d
USING (
    SELECT TO_NUMBER(TO_CHAR(day, 'YYYYMMDD'))                       AS date_key,
           day                                                        AS calendar_date,
           TRUNC(day) - TRUNC(day, 'IW') + 1                          AS day_of_week_num,
           TO_CHAR(day, 'fmDay', 'NLS_DATE_LANGUAGE=ENGLISH')         AS day_name,
           EXTRACT(DAY FROM day)                                      AS day_of_month,
           TO_NUMBER(TO_CHAR(day, 'IW'))                              AS iso_week_num,
           EXTRACT(MONTH FROM day)                                    AS month_num,
           TO_CHAR(day, 'fmMonth', 'NLS_DATE_LANGUAGE=ENGLISH')       AS month_name,
           TO_NUMBER(TO_CHAR(day, 'Q'))                               AS quarter_num,
           EXTRACT(YEAR FROM day)                                     AS year_num,
           TO_CHAR(day, 'YYYY-MM')                                    AS year_month,
           TRUNC(day, 'MM')                                           AS month_start_date,
           CASE WHEN TRUNC(day) - TRUNC(day, 'IW') >= 5 THEN 'Y' ELSE 'N' END AS is_weekend
    FROM (
        SELECT DATE '2016-01-01' + LEVEL - 1 AS day
        FROM dual
        CONNECT BY LEVEL <= DATE '2019-12-31' - DATE '2016-01-01' + 1
    )
) s
ON (d.date_key = s.date_key)
WHEN NOT MATCHED THEN INSERT (
    date_key, calendar_date, day_of_week_num, day_name, day_of_month, iso_week_num,
    month_num, month_name, quarter_num, year_num, year_month, month_start_date, is_weekend
) VALUES (
    s.date_key, s.calendar_date, s.day_of_week_num, s.day_name, s.day_of_month, s.iso_week_num,
    s.month_num, s.month_name, s.quarter_num, s.year_num, s.year_month, s.month_start_date, s.is_weekend
);

COMMIT;
