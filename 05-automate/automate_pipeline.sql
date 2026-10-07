-- ----------------------------------------------------------------------
-- Block 5 - Automate it: the whole pipeline end to end, with stored procedures + a task graph
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------
-- PIPELINE_MONTHLY (cron, 1st of the month)  CALL RUN_LOCATE(n)              step 2, new dealers only
--   -> PIPELINE_ENRICH (AFTER the root)      CALL SUBMIT_GEMINI_BATCH(n)     step 3a, sends the batch job
-- PIPELINE_COLLECT (every 5 minutes)         CALL RUN_COLLECT_AND_RESOLVE()  step 3b + step 4 when the job is done
-- Two chains because the Gemini batch is asynchronous: chain 1 starts the job, chain 2 waits for it.
-- Requires EXECUTE TASK for WORKSHOP_DEV (granted in 00-setup/admin_prereqs.sql). Run blocks 2 and 3 first (UDF + procedures).
USE ROLE WORKSHOP_DEV; USE DATABASE WORKSHOP_DB; USE SCHEMA PUBLIC; USE WAREHOUSE WORKSHOP_WH;

-- 1. Step 2 as one procedure (same statements as block 2, incremental)
CREATE OR REPLACE PROCEDURE RUN_LOCATE(MAX_DEALERS NUMBER)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    n_calls  INTEGER;
    n_placed INTEGER;
    n_cached INTEGER;
BEGIN
    CREATE TABLE IF NOT EXISTS GMAP_RESULTS (AGENCY_ID VARCHAR, SITE VARCHAR, GMAP VARIANT);

    -- 1. Call Google only for dealers never located successfully (new dealers, or previous ERROR)
    INSERT INTO GMAP_RESULTS (AGENCY_ID, SITE, GMAP)
    SELECT AGENCY_ID, SITE, FIND_GOOGLE_PLACE(AGENCY_NAME, ADDRESS, CITY, ZIP_CODE)
    FROM (SELECT d.* FROM DEALERS d
          WHERE NOT EXISTS (SELECT 1 FROM GMAP_RESULTS g
                            WHERE g.AGENCY_ID = d.AGENCY_ID AND g.SITE = d.SITE
                              AND g.GMAP:status::VARCHAR <> 'ERROR')
          ORDER BY d.AGENCY_ID
          LIMIT :MAX_DEALERS);
    n_calls := SQLROWCOUNT;

    -- 2. Store the Place ID on the dealer (same statement as block 2)
    UPDATE DEALERS d
    SET GOOGLE_PLACE_ID = g.GMAP:google_place_id::VARCHAR
    FROM GMAP_RESULTS g
    WHERE d.AGENCY_ID = g.AGENCY_ID AND d.SITE = g.SITE
      AND d.GOOGLE_PLACE_ID IS NULL
      AND g.GMAP:status::VARCHAR = 'OK';
    n_placed := SQLROWCOUNT;

    -- 3. Add new places to the rolling cache (same MERGE as block 2)
    MERGE INTO DEALER_GOOGLE_MAP t
    USING (
        SELECT GMAP:google_place_id::VARCHAR AS GOOGLE_PLACE_ID,
               GMAP:name::VARCHAR            AS AI_AGENCY_NAME,
               GMAP                          AS GOOGLE_JSON
        FROM GMAP_RESULTS
        WHERE GMAP:status::VARCHAR = 'OK'
        QUALIFY ROW_NUMBER() OVER (PARTITION BY GOOGLE_PLACE_ID ORDER BY AGENCY_ID) = 1
    ) s
    ON t.GOOGLE_PLACE_ID = s.GOOGLE_PLACE_ID
    WHEN NOT MATCHED THEN INSERT (GOOGLE_PLACE_ID, AI_AGENCY_NAME, GOOGLE_JSON)
    VALUES (s.GOOGLE_PLACE_ID, s.AI_AGENCY_NAME, s.GOOGLE_JSON);
    n_cached := SQLROWCOUNT;

    RETURN OBJECT_CONSTRUCT('google_calls', n_calls, 'place_ids_set', n_placed, 'new_cached_places', n_cached);
END;
$$;

-- 2. Step 4 as one procedure (rows not resolved yet)
CREATE OR REPLACE PROCEDURE RUN_RESOLVE()
RETURNS VARIANT
LANGUAGE SQL
AS
$$
BEGIN
    -- Same rule as block 4, only for rows not resolved yet
    UPDATE DEALER_ADDRESS_STANDARD das
    SET GOOGLE_PLACE_ID = d.GOOGLE_PLACE_ID
    FROM DEALERS d
    JOIN DEALER_GOOGLE_MAP g ON d.GOOGLE_PLACE_ID = g.GOOGLE_PLACE_ID
    WHERE das.AGENCY_ID = d.AGENCY_ID AND das.SITE = d.SITE
      AND das.GOOGLE_PLACE_ID IS NULL
      AND das.AI_JSON:potential_matches[0]:match_confidence_score::FLOAT >= 0.7
      AND CONTAINS(g.GOOGLE_JSON:formatted_address::VARCHAR,
                   das.AI_JSON:potential_matches[0]:cp::VARCHAR);
    RETURN OBJECT_CONSTRUCT('resolved', SQLROWCOUNT);
END;
$$;

-- 3. Collect the finished batch jobs, then resolve (what the polling task runs)
CREATE OR REPLACE PROCEDURE RUN_COLLECT_AND_RESOLVE()
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    collected VARIANT;
    resolved  VARIANT;
BEGIN
    -- Step 3b: load every finished Gemini batch job, then step 4 on the new rows
    CALL COLLECT_GEMINI_BATCH(NULL) INTO :collected;
    CALL RUN_RESOLVE() INTO :resolved;
    RETURN OBJECT_CONSTRUCT('collect', collected, 'resolve', resolved);
END;
$$;

-- 4. The task graph (created suspended)
-- Chain 1 (monthly): locate new dealers, then submit the Gemini batch job
CREATE OR REPLACE TASK PIPELINE_MONTHLY
    WAREHOUSE = WORKSHOP_WH
    SCHEDULE = 'USING CRON 0 6 1 * * Europe/Paris'   -- 1st of each month, 6:00 Paris time
AS
    CALL RUN_LOCATE(10  /* SAMPLE_SIZE */);

CREATE OR REPLACE TASK PIPELINE_ENRICH
    WAREHOUSE = WORKSHOP_WH
    AFTER PIPELINE_MONTHLY                            -- runs when PIPELINE_MONTHLY succeeds
AS
    CALL SUBMIT_GEMINI_BATCH(10  /* SAMPLE_SIZE */);

-- Chain 2 (polling): the batch is asynchronous, so a second task waits for it
CREATE OR REPLACE TASK PIPELINE_COLLECT
    WAREHOUSE = WORKSHOP_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL RUN_COLLECT_AND_RESOLVE();

-- 5. EXECUTE TASK skips suspended children: resume the child, keep the root suspended
-- EXECUTE TASK skips suspended child tasks: resume the child, keep the root suspended
-- (the root runs on demand now, and only on its monthly schedule once resumed in production)
ALTER TASK PIPELINE_ENRICH RESUME;
SHOW TASKS LIKE 'PIPELINE_%';

-- 6. Run the whole pipeline now, then check the history
EXECUTE TASK PIPELINE_MONTHLY;
SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME, RETURN_VALUE, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP())))
WHERE NAME LIKE 'PIPELINE_%'
ORDER BY SCHEDULED_TIME DESC;

-- 7. Collect without waiting for the 5-minute schedule (re-run after the batch is done)
EXECUTE TASK PIPELINE_COLLECT;

-- 8. Production: ALTER TASK PIPELINE_MONTHLY RESUME; ALTER TASK PIPELINE_COLLECT RESUME;
--    After the workshop: suspend everything so nothing keeps calling the APIs
ALTER TASK PIPELINE_COLLECT SUSPEND;
ALTER TASK PIPELINE_ENRICH  SUSPEND;
ALTER TASK PIPELINE_MONTHLY SUSPEND;
SHOW TASKS LIKE 'PIPELINE_%';
