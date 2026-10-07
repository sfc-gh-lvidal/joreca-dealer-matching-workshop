-- ----------------------------------------------------------------------
-- Block 3 - Enrich: paste the Gemini API key
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------

-- Same pattern as Google Maps: GEMINI_RULE (host generativelanguage.googleapis.com)
-- + GEMINI_API_KEY secret + GEMINI_EAI integration, all created by the admin
-- (00-setup/admin_prereqs.sql). You only paste the real key.
USE ROLE WORKSHOP_DEV;
-- SKIP this statement if the secret already holds the real key (e.g. set up before the workshop):
-- running it unedited would replace the key with the placeholder text.
ALTER SECRET WORKSHOP_DB.PUBLIC.GEMINI_API_KEY
    SET SECRET_STRING = 'PASTE_GEMINI_KEY_HERE';

SHOW INTEGRATIONS LIKE 'GEMINI_EAI';
DESCRIBE SECRET WORKSHOP_DB.PUBLIC.GEMINI_API_KEY;
