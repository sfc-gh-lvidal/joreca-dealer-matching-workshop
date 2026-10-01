----------------------------------------------------------------------
-- Setup External Access Integration for Google Maps API
----------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;
USE DATABASE WORKSHOP_DB;
USE SCHEMA PUBLIC;

-- 1. Network Rule: allow outbound HTTPS to Google Maps APIs
CREATE OR REPLACE NETWORK RULE google_maps_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('maps.googleapis.com', 'places.googleapis.com');

-- 2. Secret: store the Google Maps API key securely
--    REPLACE 'YOUR_GOOGLE_MAPS_API_KEY' with the real key
CREATE OR REPLACE SECRET google_maps_api_key
    TYPE = GENERIC_STRING
    SECRET_STRING = 'YOUR_GOOGLE_MAPS_API_KEY';

-- 3. External Access Integration
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION google_maps_eai
    ALLOWED_NETWORK_RULES = (google_maps_rule)
    ALLOWED_AUTHENTICATION_SECRETS = (google_maps_api_key)
    ENABLED = TRUE;

-- 4. Grant to SYSADMIN
GRANT USAGE ON INTEGRATION google_maps_eai TO ROLE SYSADMIN;

DESCRIBE INTEGRATION google_maps_eai;
