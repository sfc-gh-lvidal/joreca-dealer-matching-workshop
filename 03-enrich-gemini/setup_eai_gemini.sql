----------------------------------------------------------------------
-- Setup External Access Integration for Gemini API
----------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;
USE DATABASE WORKSHOP_DB;
USE SCHEMA PUBLIC;

-- 1. Network Rule
CREATE OR REPLACE NETWORK RULE gemini_api_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('generativelanguage.googleapis.com');

-- 2. Secret — REPLACE with your actual Gemini API key
CREATE OR REPLACE SECRET gemini_api_key
    TYPE = GENERIC_STRING
    SECRET_STRING = 'YOUR_GEMINI_API_KEY';

-- 3. External Access Integration
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION gemini_eai
    ALLOWED_NETWORK_RULES = (gemini_api_rule)
    ALLOWED_AUTHENTICATION_SECRETS = (gemini_api_key)
    ENABLED = TRUE;

-- 4. Grant to SYSADMIN
GRANT USAGE ON INTEGRATION gemini_eai TO ROLE SYSADMIN;

DESCRIBE INTEGRATION gemini_eai;
