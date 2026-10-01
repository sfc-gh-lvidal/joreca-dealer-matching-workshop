-- ----------------------------------------------------------------------
-- Block 0 - Setup: database, warehouse, stage, tables, data load
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------

-- Everything lives in a dedicated database: drop it after the workshop to clean up.
-- SYSADMIN owns the objects; ACCOUNTADMIN is only needed for the integrations (blocks 2 and 3).
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS WORKSHOP_DB;
USE DATABASE WORKSHOP_DB;
USE SCHEMA PUBLIC;

-- XSMALL is enough: the heavy work is done by the external APIs, not by the warehouse.
-- AUTO_SUSPEND = 60 s so the warehouse stops costing credits when idle.
CREATE WAREHOUSE IF NOT EXISTS WORKSHOP_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
USE WAREHOUSE WORKSHOP_WH;

-- Internal stage = Snowflake-managed file storage. It replaces the local folders of the Linux server.
-- Upload the files from your terminal with Snow CLI (run from the repo root):
--   snow stage copy data/dealers_sample.csv @WORKSHOP_DB.PUBLIC.WORKSHOP_STAGE
--   snow stage copy prompts/gemini_search_agency.txt @WORKSHOP_DB.PUBLIC.WORKSHOP_STAGE/prompts
CREATE STAGE IF NOT EXISTS WORKSHOP_STAGE;
LIST @WORKSHOP_STAGE;   -- you should see both files

-- DEALERS = step 1 output (Collect): one row per dealer per marketplace site.
-- Same name and key as the target architecture: (AGENCY_ID, SITE).
-- Note: Snowflake does not enforce PRIMARY KEY uniqueness (only NOT NULL); it documents the model.
CREATE OR REPLACE TABLE DEALERS (
    AGENCY_ID       VARCHAR,
    SITE            VARCHAR,
    AGENCY_NAME     VARCHAR,
    ADDRESS         VARCHAR,
    CITY            VARCHAR,
    ZIP_CODE        VARCHAR,
    SIRET           VARCHAR,
    MINISITE_URL    VARCHAR,
    GOOGLE_PLACE_ID VARCHAR,   -- filled in step 2
    JORECA_ID       VARCHAR,   -- filled in step 6 (out of scope)
    PRIMARY KEY (AGENCY_ID, SITE)
);

-- Load the crawl sample from the stage. Equivalent of the INSERTs into MariaDB.
-- The CSV columns are SITE, AGENCY_ID, ... so we list the target columns in that order.
-- EMPTY_FIELD_AS_NULL turns empty strings (e.g. missing SIRET) into real NULLs.
COPY INTO DEALERS (SITE, AGENCY_ID, AGENCY_NAME, ADDRESS, CITY, ZIP_CODE, SIRET, MINISITE_URL)
FROM @WORKSHOP_STAGE/dealers_sample.csv
FILE_FORMAT = (TYPE='CSV' FIELD_OPTIONALLY_ENCLOSED_BY='"' SKIP_HEADER=1 EMPTY_FIELD_AS_NULL=TRUE);

-- Empty tables for steps 2 and 3, same names as the target architecture.
-- DEALER_GOOGLE_MAP: rolling cache keyed by GOOGLE_PLACE_ID -> a place is fetched once and reused every month.
-- DEALER_ADDRESS_STANDARD: per-period workspace (one row per AGENCY_ID, SITE) holding the Gemini output.
CREATE OR REPLACE TABLE DEALER_GOOGLE_MAP (
    GOOGLE_PLACE_ID VARCHAR PRIMARY KEY,
    AI_AGENCY_NAME  VARCHAR,
    GOOGLE_JSON     VARIANT,
    CREATED_AT      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
CREATE OR REPLACE TABLE DEALER_ADDRESS_STANDARD (
    AGENCY_ID           VARCHAR,
    SITE                VARCHAR,
    GOOGLE_PLACE_ID     VARCHAR,
    JORECA_ID           VARCHAR,
    IS_REUSED           BOOLEAN DEFAULT FALSE,
    AI_JSON             VARIANT,
    AI_STANDARD_ADDRESS VARCHAR,
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (AGENCY_ID, SITE)
);

-- Expected: DEALERS = 200, the two other tables = 0 at this point.
SELECT 'DEALERS' AS TBL, COUNT(*) AS N FROM DEALERS
UNION ALL SELECT 'DEALER_GOOGLE_MAP', COUNT(*) FROM DEALER_GOOGLE_MAP
UNION ALL SELECT 'DEALER_ADDRESS_STANDARD', COUNT(*) FROM DEALER_ADDRESS_STANDARD;
