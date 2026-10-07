# [OPTIONAL] Data Quality — DMFs for Dealer Matching

> **Edition:** Data Metric Functions require **Enterprise Edition** or higher. On a Standard account,
> the `ALTER TABLE ... ADD DATA METRIC FUNCTION` statements fail. Use the Standard-compatible
> alternative at the end of this page instead (same checks, plain SQL + a Task).

## Goal

Set up automated data quality checks on your enriched dealer data using Snowflake Data Metric Functions (DMFs).

## Suggested DMFs

```sql
-- 1. Address standardization completeness
CREATE OR REPLACE DATA METRIC FUNCTION address_completeness_pct(
    ARG_T TABLE(AI_STANDARD_ADDRESS VARCHAR)
)
RETURNS NUMBER AS
$$ SELECT ROUND(COUNT(AI_STANDARD_ADDRESS) / NULLIF(COUNT(*), 0) * 100, 1) FROM ARG_T $$;

-- 2. SIRET coverage
CREATE OR REPLACE DATA METRIC FUNCTION siret_coverage_pct(
    ARG_T TABLE(SIRET VARCHAR)
)
RETURNS NUMBER AS
$$ SELECT ROUND(SUM(CASE WHEN SIRET != '' AND SIRET IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) * 100, 1) FROM ARG_T $$;

-- 3. Google Place ID resolution rate
CREATE OR REPLACE DATA METRIC FUNCTION place_id_rate_pct(
    ARG_T TABLE(GOOGLE_PLACE_ID VARCHAR)
)
RETURNS NUMBER AS
$$ SELECT ROUND(COUNT(GOOGLE_PLACE_ID) / NULLIF(COUNT(*), 0) * 100, 1) FROM ARG_T $$;

-- Attach to tables
ALTER TABLE DEALER_ADDRESS_STANDARD SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';
ALTER TABLE DEALER_ADDRESS_STANDARD ADD DATA METRIC FUNCTION address_completeness_pct ON (AI_STANDARD_ADDRESS);
ALTER TABLE DEALER_ADDRESS_STANDARD ADD DATA METRIC FUNCTION place_id_rate_pct ON (GOOGLE_PLACE_ID);
ALTER TABLE DEALERS ADD DATA METRIC FUNCTION siret_coverage_pct ON (SIRET);
```

## Standard Edition alternative (no DMFs)

The same checks as a plain view, which you can query after each monthly run or snapshot with a Task (block 09):

```sql
USE ROLE WORKSHOP_DEV; USE SCHEMA WORKSHOP_DB.PUBLIC; USE WAREHOUSE WORKSHOP_WH;

CREATE OR REPLACE VIEW DQ_CHECKS AS
SELECT 'DEALERS: missing SIRET'               AS CHECK_NAME, COUNT_IF(SIRET IS NULL)         AS FAILED_ROWS, COUNT(*) AS TOTAL_ROWS FROM DEALERS
UNION ALL
SELECT 'DEALERS: duplicate (AGENCY_ID, SITE)', COUNT(*) - COUNT(DISTINCT AGENCY_ID, SITE),                 COUNT(*)            FROM DEALERS
UNION ALL
SELECT 'DAS: no standardized address',        COUNT_IF(AI_STANDARD_ADDRESS IS NULL),                      COUNT(*)            FROM DEALER_ADDRESS_STANDARD
UNION ALL
SELECT 'DAS: Gemini call in error',           COUNT_IF(AI_JSON:error IS NOT NULL),                        COUNT(*)            FROM DEALER_ADDRESS_STANDARD
UNION ALL
SELECT 'DAS: rows older than 35 days',        COUNT_IF(CREATED_AT < DATEADD(day, -35, CURRENT_TIMESTAMP())), COUNT(*)         FROM DEALER_ADDRESS_STANDARD;

SELECT * FROM DQ_CHECKS;
```

