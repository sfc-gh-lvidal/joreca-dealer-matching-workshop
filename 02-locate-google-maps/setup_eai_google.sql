-- ----------------------------------------------------------------------
-- Block 2 - Locate: External Access Integration for Google Maps (ACCOUNTADMIN)
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------

-- Snowflake blocks all outbound network calls by default. Three objects open a controlled path:
--   1. NETWORK RULE: which hosts are reachable (only Google Maps here)
--   2. SECRET: the API key, stored encrypted; code reads it at runtime, it is never visible in SQL
--   3. EXTERNAL ACCESS INTEGRATION: binds rule + secret; UDFs must reference it explicitly
-- Requires ACCOUNTADMIN (or CREATE INTEGRATION privilege). Run once.
-- On the Google Cloud project, the Places API (findplacefromtext + details endpoints) must be enabled.
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE NETWORK RULE WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_RULE
    MODE = EGRESS TYPE = HOST_PORT
    VALUE_LIST = ('maps.googleapis.com');
CREATE OR REPLACE SECRET WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_API_KEY
    TYPE = GENERIC_STRING
    SECRET_STRING = 'PASTE_GOOGLE_MAPS_KEY_HERE';
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION GOOGLE_MAPS_EAI
    ALLOWED_NETWORK_RULES = (WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_RULE)
    ALLOWED_AUTHENTICATION_SECRETS = (WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_API_KEY)
    ENABLED = TRUE;
GRANT USAGE ON INTEGRATION GOOGLE_MAPS_EAI TO ROLE SYSADMIN;
GRANT READ ON SECRET WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_API_KEY TO ROLE SYSADMIN;
USE ROLE SYSADMIN;
