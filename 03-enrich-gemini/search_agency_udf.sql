-- ----------------------------------------------------------------------
-- Block 3 - Enrich: UDF SEARCH_AGENCY (Joreca prompt + Google Search grounding) -> DEALER_ADDRESS_STANDARD
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------
USE ROLE SYSADMIN; USE DATABASE WORKSHOP_DB; USE SCHEMA PUBLIC; USE WAREHOUSE WORKSHOP_WH;

-- Replaces the Gemini batch flow (export JSON file -> upload -> wait -> download -> re-import).
-- Here each row calls Gemini directly and the answer lands in a table.
-- The prompt is Joreca's production prompt, read from a file on the stage (IMPORTS):
-- to change the prompt, re-upload the file and re-run this CREATE FUNCTION; no code change needed.
-- tools = google_search enables web research (grounding), as required by the prompt.
-- usageMetadata (input/output tokens) is kept in the result to measure the real cost per dealer.
CREATE OR REPLACE FUNCTION SEARCH_AGENCY(AGENCY_NAME VARCHAR, ADDRESS VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('requests')
IMPORTS = ('@WORKSHOP_DB.PUBLIC.WORKSHOP_STAGE/prompts/gemini_search_agency.txt')
HANDLER = 'search'
EXTERNAL_ACCESS_INTEGRATIONS = (GEMINI_EAI)
SECRETS = ('gemini_key' = WORKSHOP_DB.PUBLIC.GEMINI_API_KEY)
AS
$$
import _snowflake
import json
import os
import re
import sys
import requests

MODEL = "gemini-2.5-flash"
# Joreca's production prompt, versioned as a file on the stage
with open(os.path.join(sys._xoptions["snowflake_import_directory"], "gemini_search_agency.txt"), encoding="utf-8") as f:
    SYSTEM_PROMPT = f.read()

def _parse(text):
    text = text.strip()
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text)
    start, end = text.find("{"), text.rfind("}")
    return json.loads(text[start:end + 1])

def search(agency_name, address):
    key = _snowflake.get_generic_secret_string('gemini_key')
    user_input = f"Agency Name: {agency_name}\nAddress: {address}"
    body = {
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": [{"role": "user", "parts": [{"text": user_input}]}],
        "tools": [{"google_search": {}}],          # online research, as in their batch setup
        "generationConfig": {"temperature": 0.1},
    }
    try:
        r = requests.post(
            f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent",
            headers={"x-goog-api-key": key}, json=body, timeout=120)
        if r.status_code != 200:
            return {"error": f"HTTP {r.status_code}: {r.json().get('error', {}).get('message', r.text[:300])}"}
        resp = r.json()
        text = "".join(p.get("text", "") for p in resp["candidates"][0]["content"]["parts"])
        out = _parse(text)
        out["_usage"] = resp.get("usageMetadata")   # input/output tokens, for cost tracking
        return out
    except Exception as e:
        return {"error": f"{type(e).__name__}: {e}"}
$$;

-- Same inputs as the batch: 'Agency Name' and one 'Address' string.
-- Each call does web research: expect several seconds per dealer.
SELECT AGENCY_NAME,
       SEARCH_AGENCY(AGENCY_NAME, CONCAT_WS(', ', ADDRESS, ZIP_CODE, CITY, 'France')) AS AI
FROM DEALERS
LIMIT 3;

-- Run the search for SAMPLE_SIZE dealers and store the full JSON in AI_JSON.
-- AI_STANDARD_ADDRESS is extracted from potential_matches[0].standard_address (format defined in the prompt).
-- IS_REUSED = FALSE: in production, skip the call when last month already has a result for (AGENCY_ID, SITE).
INSERT INTO DEALER_ADDRESS_STANDARD (AGENCY_ID, SITE, AI_JSON, AI_STANDARD_ADDRESS, IS_REUSED)
SELECT AGENCY_ID, SITE, AI, AI:potential_matches[0]:standard_address::VARCHAR, FALSE
FROM (
    SELECT AGENCY_ID, SITE,
           SEARCH_AGENCY(AGENCY_NAME, CONCAT_WS(', ', ADDRESS, ZIP_CODE, CITY, 'France')) AS AI
    FROM (SELECT * FROM DEALERS ORDER BY AGENCY_ID LIMIT 10  /* SAMPLE_SIZE: number of dealers sent to the APIs */)
);

-- Parse the JSON with the : and [] notation. The ERROR column must be empty.
SELECT AGENCY_ID, SITE,
       AI_JSON:overall_search_status::VARCHAR                          AS SEARCH_STATUS,
       AI_JSON:potential_matches[0]:found_agency_name::VARCHAR         AS FOUND_NAME,
       AI_STANDARD_ADDRESS,
       AI_JSON:potential_matches[0]:establishment_level_number::VARCHAR AS AI_SIRET,
       AI_JSON:potential_matches[0]:match_confidence_score::FLOAT      AS CONFIDENCE,
       AI_JSON:_usage:promptTokenCount::NUMBER                         AS INPUT_TOKENS,
       AI_JSON:_usage:candidatesTokenCount::NUMBER                     AS OUTPUT_TOKENS,
       AI_JSON:error::VARCHAR                                          AS ERROR
FROM DEALER_ADDRESS_STANDARD;

-- Real token consumption per call: input to the Gemini vs Cortex AI cost comparison.
SELECT COUNT(*) AS CALLS,
       ROUND(AVG(AI_JSON:_usage:promptTokenCount::NUMBER))     AS AVG_INPUT_TOKENS,
       ROUND(AVG(AI_JSON:_usage:candidatesTokenCount::NUMBER)) AS AVG_OUTPUT_TOKENS,
       ROUND(AVG(AI_JSON:_usage:totalTokenCount::NUMBER))      AS AVG_TOTAL_TOKENS
FROM DEALER_ADDRESS_STANDARD
WHERE AI_JSON:error IS NULL;
