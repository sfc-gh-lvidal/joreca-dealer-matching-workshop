-- ----------------------------------------------------------------------
-- Block 0 (ADMIN, run ONCE before the workshop) - Account-level prerequisites
-- Run by the participant who holds ACCOUNTADMIN. Takes ~1 minute.
--
-- Everything that requires ACCOUNTADMIN is done here, so the other
-- developers can run the whole workshop with a single role: WORKSHOP_DEV.
--   - WORKSHOP_DEV role, granted to each developer
--   - WORKSHOP_WH warehouse + WORKSHOP_DB database, owned by WORKSHOP_DEV
--   - network rules + secrets (placeholder keys) for Google Maps and Gemini
--   - the 3 integrations (Google Maps, Gemini, GitHub), usable by WORKSHOP_DEV
-- ----------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;

-- 1. Workshop role -------------------------------------------------------
-- Attached under SYSADMIN (best practice: admins can still see/manage the objects).
CREATE ROLE IF NOT EXISTS WORKSHOP_DEV COMMENT = 'Joreca workshop - developers';
GRANT ROLE WORKSHOP_DEV TO ROLE SYSADMIN;

-- Give the role to every developer (and to yourself). Replace the user names.
GRANT ROLE WORKSHOP_DEV TO USER TA_HAPHAM;
-- GRANT ROLE WORKSHOP_DEV TO USER <DEV_2>;
-- GRANT ROLE WORKSHOP_DEV TO USER <DEV_3>;
-- GRANT ROLE WORKSHOP_DEV TO USER <DEV_4>;

-- 2. Compute + database --------------------------------------------------
-- XSMALL is enough: the heavy work is done by the external APIs.
CREATE WAREHOUSE IF NOT EXISTS WORKSHOP_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
GRANT USAGE, OPERATE ON WAREHOUSE WORKSHOP_WH TO ROLE WORKSHOP_DEV;

-- WORKSHOP_DEV owns the database and its schema: devs create stage, tables, UDFs, views freely.
CREATE DATABASE IF NOT EXISTS WORKSHOP_DB;
GRANT OWNERSHIP ON DATABASE WORKSHOP_DB TO ROLE WORKSHOP_DEV COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA WORKSHOP_DB.PUBLIC TO ROLE WORKSHOP_DEV COPY CURRENT GRANTS;

-- 3. Network rules + secrets ---------------------------------------------
-- They must exist before the integrations that reference them.
-- Snowflake blocks all outbound calls by default; a network rule lists the allowed hosts.
CREATE OR REPLACE NETWORK RULE WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_RULE
    MODE = EGRESS TYPE = HOST_PORT VALUE_LIST = ('maps.googleapis.com');
CREATE OR REPLACE NETWORK RULE WORKSHOP_DB.PUBLIC.GEMINI_RULE
    MODE = EGRESS TYPE = HOST_PORT VALUE_LIST = ('generativelanguage.googleapis.com');

-- Placeholder values: the developers paste the real keys during the workshop (ALTER SECRET).
CREATE OR REPLACE SECRET WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_API_KEY
    TYPE = GENERIC_STRING SECRET_STRING = 'REPLACE_ME';
CREATE OR REPLACE SECRET WORKSHOP_DB.PUBLIC.GEMINI_API_KEY
    TYPE = GENERIC_STRING SECRET_STRING = 'REPLACE_ME';

-- 4. Integrations (the only objects that really need ACCOUNTADMIN) -------
-- External Access Integration = network rule + secret that UDFs are allowed to use.
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION GOOGLE_MAPS_EAI
    ALLOWED_NETWORK_RULES = (WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_RULE)
    ALLOWED_AUTHENTICATION_SECRETS = (WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_API_KEY)
    ENABLED = TRUE;
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION GEMINI_EAI
    ALLOWED_NETWORK_RULES = (WORKSHOP_DB.PUBLIC.GEMINI_RULE)
    ALLOWED_AUTHENTICATION_SECRETS = (WORKSHOP_DB.PUBLIC.GEMINI_API_KEY)
    ENABLED = TRUE;

-- API integration = lets Snowsight create a Git workspace from the public workshop repo.
-- No secret: the repo is public, so workspaces can pull but not push.
CREATE OR REPLACE API INTEGRATION GITHUB_WORKSHOP_API
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-lvidal')
    ENABLED = TRUE;

GRANT USAGE ON INTEGRATION GOOGLE_MAPS_EAI     TO ROLE WORKSHOP_DEV;
GRANT USAGE ON INTEGRATION GEMINI_EAI          TO ROLE WORKSHOP_DEV;
GRANT USAGE ON INTEGRATION GITHUB_WORKSHOP_API TO ROLE WORKSHOP_DEV;

-- 5. Hand the secrets and network rules over to WORKSHOP_DEV ------------
-- Ownership lets developers paste the real keys (ALTER SECRET) and the UDFs read them.
GRANT OWNERSHIP ON SECRET WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_API_KEY TO ROLE WORKSHOP_DEV;
GRANT OWNERSHIP ON SECRET WORKSHOP_DB.PUBLIC.GEMINI_API_KEY      TO ROLE WORKSHOP_DEV;
GRANT OWNERSHIP ON NETWORK RULE WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_RULE TO ROLE WORKSHOP_DEV;
GRANT OWNERSHIP ON NETWORK RULE WORKSHOP_DB.PUBLIC.GEMINI_RULE      TO ROLE WORKSHOP_DEV;

-- Optional block 06 (Cortex AI): CORTEX_USER is granted to PUBLIC by default.
-- If your admin revoked it, uncomment:
-- GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE WORKSHOP_DEV;

-- Optional block 09 (Scheduling with Tasks): running a task needs this account-level privilege.
-- GRANT EXECUTE TASK ON ACCOUNT TO ROLE WORKSHOP_DEV;

-- 6. Check ---------------------------------------------------------------
SHOW GRANTS TO ROLE WORKSHOP_DEV;

-- ----------------------------------------------------------------------
-- CLEANUP after the workshop (ACCOUNTADMIN):
-- DROP INTEGRATION IF EXISTS GOOGLE_MAPS_EAI;
-- DROP INTEGRATION IF EXISTS GEMINI_EAI;
-- DROP INTEGRATION IF EXISTS GITHUB_WORKSHOP_API;
-- DROP DATABASE IF EXISTS WORKSHOP_DB;
-- DROP WAREHOUSE IF EXISTS WORKSHOP_WH;
-- DROP ROLE IF EXISTS WORKSHOP_DEV;
-- ----------------------------------------------------------------------
