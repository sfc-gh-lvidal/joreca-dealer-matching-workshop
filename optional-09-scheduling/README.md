# [OPTIONAL] Scheduling — Snowflake Tasks for Monthly Runs

## Goal

Orchestrate the dealer matching pipeline with Snowflake Tasks so it runs automatically on a schedule (monthly, after each crawl batch).

## Approach

Create a task graph that chains the pipeline steps:

```sql
-- Root task: runs monthly on the 1st at 6:00 AM Paris time
CREATE OR REPLACE TASK pipeline_step1_collect
    WAREHOUSE = WORKSHOP_WH
    SCHEDULE = 'USING CRON 0 6 1 * * Europe/Paris'
AS
    CALL collect_dealers();  -- Your stored procedure for step 1

-- Step 2: runs after step 1 completes
CREATE OR REPLACE TASK pipeline_step2_locate
    WAREHOUSE = WORKSHOP_WH
    AFTER pipeline_step1_collect
AS
    CALL locate_google_maps();

-- Step 3: runs after step 2
CREATE OR REPLACE TASK pipeline_step3_enrich
    WAREHOUSE = WORKSHOP_WH
    AFTER pipeline_step2_locate
AS
    CALL enrich_gemini();

-- Step 4: runs after step 3
CREATE OR REPLACE TASK pipeline_step4_resolve
    WAREHOUSE = WORKSHOP_WH
    AFTER pipeline_step3_enrich
AS
    CALL resolve_place_ids();

-- Resume the root task (tasks are created suspended by default)
ALTER TASK pipeline_step1_collect RESUME;
```

## Alternative: Stream-triggered tasks

Instead of a schedule, trigger the pipeline when new crawl data lands:

```sql
CREATE STREAM new_dealers_stream ON TABLE DEALERS;

CREATE OR REPLACE TASK pipeline_on_new_data
    WAREHOUSE = WORKSHOP_WH
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('new_dealers_stream')
AS
    CALL run_full_pipeline();
```

## Monitoring

Use `TASK_HISTORY()` and `PIPELINE_RUN_LOG` (from Joreca's architecture) to track execution:

```sql
SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE NAME LIKE 'PIPELINE_%'
ORDER BY SCHEDULED_TIME DESC;
```
