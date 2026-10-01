-- ----------------------------------------------------------------------
-- Block 3 - Enrich: External Access Integration for Gemini (ACCOUNTADMIN)
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------

-- Same pattern as Google Maps: network rule + secret + integration, for the Gemini API host.
-- Requires ACCOUNTADMIN. Run once.
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE NETWORK RULE WORKSHOP_DB.PUBLIC.GEMINI_RULE
    MODE = EGRESS TYPE = HOST_PORT
    VALUE_LIST = ('generativelanguage.googleapis.com');
CREATE OR REPLACE SECRET WORKSHOP_DB.PUBLIC.GEMINI_API_KEY
    TYPE = GENERIC_STRING
    SECRET_STRING = 'PASTE_GEMINI_KEY_HERE';
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION GEMINI_EAI
    ALLOWED_NETWORK_RULES = (WORKSHOP_DB.PUBLIC.GEMINI_RULE)
    ALLOWED_AUTHENTICATION_SECRETS = (WORKSHOP_DB.PUBLIC.GEMINI_API_KEY)
    ENABLED = TRUE;
GRANT USAGE ON INTEGRATION GEMINI_EAI TO ROLE SYSADMIN;
GRANT READ ON SECRET WORKSHOP_DB.PUBLIC.GEMINI_API_KEY TO ROLE SYSADMIN;
USE ROLE SYSADMIN;
