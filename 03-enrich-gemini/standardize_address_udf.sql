----------------------------------------------------------------------
-- Gemini UDF: Address standardization → DEALER_ADDRESS_STANDARD
----------------------------------------------------------------------

USE ROLE SYSADMIN;
USE DATABASE WORKSHOP_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE WORKSHOP_WH;

-- 1. Create the UDF
CREATE OR REPLACE FUNCTION standardize_address(
    agency_name VARCHAR,
    address_raw VARCHAR,
    city VARCHAR,
    zip_code VARCHAR,
    google_place_name VARCHAR,
    google_formatted_address VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('requests')
HANDLER = 'standardize'
EXTERNAL_ACCESS_INTEGRATIONS = (gemini_eai)
SECRETS = ('gemini_key' = gemini_api_key)
AS
$$
import _snowflake
import requests
import json

def standardize(agency_name: str, address_raw: str, city: str, zip_code: str,
                google_place_name: str, google_formatted_address: str) -> dict:
    api_key = _snowflake.get_generic_secret_string('gemini_key')
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"

    google_context = ""
    if google_place_name or google_formatted_address:
        google_context = f"""
Google Maps found this business:
- Name: {google_place_name or 'N/A'}
- Address: {google_formatted_address or 'N/A'}
"""

    prompt = f"""You are a data enrichment assistant for a French automotive dealer directory.

Given a raw dealer record from a marketplace crawl and optional Google Maps data, standardize the address and verify the dealer identity.

RAW DEALER DATA:
- Agency name: {agency_name}
- Address: {address_raw}
- City: {city}
- Zip code: {zip_code}
{google_context}
TASKS:
1. Produce a standardized, complete French postal address (street number, street name, postal code, city, France)
2. If Google Maps data is available, assess whether it matches the raw dealer (same business at same location)
3. Clean up the agency name (proper capitalization, expand abbreviations)

Return ONLY a valid JSON object:
{{
  "standard_address": "full standardized address",
  "standard_city": "city name",
  "standard_zip_code": "postal code",
  "clean_agency_name": "cleaned dealer name",
  "google_match": true/false (does Google Maps data match this dealer?),
  "google_match_reason": "brief explanation",
  "confidence": 0.0-1.0
}}"""

    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": 500}
    }

    try:
        resp = requests.post(url, json=payload, timeout=30)
        resp.raise_for_status()
        text = resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()

        # Strip markdown code fences if present
        if text.startswith("```"):
            text = text.split("\n", 1)[1]
        if text.endswith("```"):
            text = text.rsplit("```", 1)[0]
        text = text.strip()

        return json.loads(text)
    except Exception as e:
        return {
            "error": str(e),
            "standard_address": None,
            "confidence": 0.0
        }
$$;

-- 2. Test on 3 rows (joining with DEALER_GOOGLE_MAP for context)
SELECT
    d.AGENCY_ID, d.SITE, d.AGENCY_NAME,
    standardize_address(
        d.AGENCY_NAME, d.ADDRESS, d.CITY, d.ZIP_CODE,
        gm.AI_AGENCY_NAME,
        gm.GOOGLE_JSON:"formatted_address"::VARCHAR
    ) AS AI_RESULT
FROM DEALERS d
LEFT JOIN DEALER_GOOGLE_MAP gm
    ON gm.GOOGLE_PLACE_ID = (
        -- Find the Google Place ID for this dealer from our earlier lookup
        SELECT VALUE:"google_place_id"::VARCHAR
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))  -- In practice, join via a lookup table
        LIMIT 1
    )
LIMIT 3;

-- NOTE: The join above is simplified for the workshop. In practice, you'd store
-- the GOOGLE_PLACE_ID mapping from step 2 in a separate lookup table or in DEALERS itself.
-- For the workshop, we'll use a simpler approach:

-- 3. Populate DEALER_ADDRESS_STANDARD (simplified: call Gemini without Google Maps context first)
INSERT INTO DEALER_ADDRESS_STANDARD (AGENCY_ID, SITE, AI_JSON, AI_STANDARD_ADDRESS, IS_REUSED)
SELECT
    d.AGENCY_ID,
    d.SITE,
    ai.VALUE AS AI_JSON,
    ai.VALUE:"standard_address"::VARCHAR AS AI_STANDARD_ADDRESS,
    FALSE AS IS_REUSED
FROM DEALERS d,
LATERAL (
    SELECT standardize_address(
        d.AGENCY_NAME, d.ADDRESS, d.CITY, d.ZIP_CODE,
        NULL, NULL  -- No Google Maps context for now; in production, join with DEALER_GOOGLE_MAP
    ) AS VALUE
) ai;

-- 4. Update with Google Maps context where available
-- (This is the "resolve" part — step 4 will refine this further)

-- 5. Check results
SELECT COUNT(*) AS STANDARDIZED_COUNT FROM DEALER_ADDRESS_STANDARD;

SELECT
    AGENCY_ID, SITE,
    AI_STANDARD_ADDRESS,
    AI_JSON:"clean_agency_name"::VARCHAR AS CLEAN_NAME,
    AI_JSON:"confidence"::FLOAT AS CONFIDENCE
FROM DEALER_ADDRESS_STANDARD
ORDER BY CONFIDENCE DESC
LIMIT 15;
