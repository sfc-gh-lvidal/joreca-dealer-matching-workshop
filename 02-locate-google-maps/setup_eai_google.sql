-- ----------------------------------------------------------------------
-- Block 2 - Locate: paste the Google Maps API key
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------

-- Snowflake blocks all outbound network calls by default. Three objects open a controlled path:
--   1. NETWORK RULE GOOGLE_MAPS_RULE: which hosts are reachable (only maps.googleapis.com)
--   2. SECRET GOOGLE_MAPS_API_KEY: the API key, stored encrypted; code reads it at runtime, never visible in SQL
--   3. EXTERNAL ACCESS INTEGRATION GOOGLE_MAPS_EAI: binds rule + secret; UDFs must reference it explicitly
-- The admin already created all three (00-setup/admin_prereqs.sql), with a placeholder key.
-- WORKSHOP_DEV owns the secret, so you only paste the real key here.
-- On the Google Cloud project, the Places API (findplacefromtext + details endpoints) must be enabled.
USE ROLE WORKSHOP_DEV;
ALTER SECRET WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_API_KEY
    SET SECRET_STRING = 'PASTE_GOOGLE_MAPS_KEY_HERE';

-- Check: the integration is visible to your role (the key value is never shown).
SHOW INTEGRATIONS LIKE 'GOOGLE_MAPS_EAI';
DESCRIBE SECRET WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_API_KEY;
