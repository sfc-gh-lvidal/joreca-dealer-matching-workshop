-- ----------------------------------------------------------------------
-- Block 2 - Locate: UDF FIND_GOOGLE_PLACE -> DEALERS.GOOGLE_PLACE_ID + DEALER_GOOGLE_MAP
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------
USE ROLE WORKSHOP_DEV; USE DATABASE WORKSHOP_DB; USE SCHEMA PUBLIC; USE WAREHOUSE WORKSHOP_WH;

-- Python UDF = your Python script, executed by Snowflake on each row. No server, no cron, no file I/O.
-- It returns a VARIANT (JSON) so we keep the full Google answer and parse it in SQL afterwards.
-- status values: OK / NOT_FOUND (no result) / ERROR (bad key, quota, API disabled...: see the error field).
CREATE OR REPLACE FUNCTION FIND_GOOGLE_PLACE(AGENCY_NAME VARCHAR, ADDRESS VARCHAR, CITY VARCHAR, ZIP_CODE VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('requests')
HANDLER = 'find_place'
EXTERNAL_ACCESS_INTEGRATIONS = (GOOGLE_MAPS_EAI)
SECRETS = ('gmap_key' = WORKSHOP_DB.PUBLIC.GOOGLE_MAPS_API_KEY)
AS
$$
import _snowflake
import requests

def find_place(agency_name, address, city, zip_code):
    key = _snowflake.get_generic_secret_string('gmap_key')
    query = ', '.join(p for p in [agency_name, address, zip_code, city] if p)
    try:
        r = requests.get(
            "https://maps.googleapis.com/maps/api/place/findplacefromtext/json",
            params={"input": query, "inputtype": "textquery",
                    "fields": "place_id", "language": "fr", "key": key},
            timeout=15)
        r.raise_for_status()
        data = r.json()
        if data.get("status") == "ZERO_RESULTS":
            return {"status": "NOT_FOUND", "query": query}
        if data.get("status") != "OK":
            # REQUEST_DENIED (bad key / API not enabled), OVER_QUERY_LIMIT, INVALID_REQUEST...
            return {"status": "ERROR", "query": query,
                    "error": f"{data.get('status')}: {data.get('error_message', '')}"}
        cands = data["candidates"]
        place_id = cands[0]["place_id"]
        d = requests.get(
            "https://maps.googleapis.com/maps/api/place/details/json",
            params={"place_id": place_id, "language": "fr", "key": key,
                    "fields": "place_id,name,formatted_address,formatted_phone_number,website,geometry,business_status,types"},
            timeout=15)
        d.raise_for_status()
        res = d.json().get("result", {})
        loc = res.get("geometry", {}).get("location", {})
        return {"status": "OK", "query": query, "google_place_id": place_id,
                "name": res.get("name"), "formatted_address": res.get("formatted_address"),
                "phone": res.get("formatted_phone_number"), "website": res.get("website"),
                "latitude": loc.get("lat"), "longitude": loc.get("lng"),
                "business_status": res.get("business_status"), "types": res.get("types", [])}
    except Exception as e:
        # type only: requests errors embed the URL, which contains the API key
        return {"status": "ERROR", "query": query, "error": type(e).__name__}
$$;

-- Always test on a few rows first: each call is billed by Google.
SELECT AGENCY_NAME, FIND_GOOGLE_PLACE(AGENCY_NAME, ADDRESS, CITY, ZIP_CODE) AS GMAP
FROM DEALERS LIMIT 3;

-- Call the API ONCE per dealer and keep the raw results in a table.
-- The next cells reuse this table instead of calling the API again.
-- 10  /* SAMPLE_SIZE: number of dealers sent to the APIs */ is the Python variable defined at the top of the notebook (Jinja templating).
CREATE OR REPLACE TABLE GMAP_RESULTS AS
SELECT AGENCY_ID, SITE, FIND_GOOGLE_PLACE(AGENCY_NAME, ADDRESS, CITY, ZIP_CODE) AS GMAP
FROM (SELECT * FROM DEALERS ORDER BY AGENCY_ID LIMIT 10  /* SAMPLE_SIZE: number of dealers sent to the APIs */);

-- Check before going further: if everything is ERROR, read the error field (usually the key or a disabled API).
SELECT GMAP:status::VARCHAR AS STATUS, COUNT(*) AS N FROM GMAP_RESULTS GROUP BY 1;

-- Store the Place ID on the dealer row (DEALERS.GOOGLE_PLACE_ID, as in the target architecture).
UPDATE DEALERS d
SET GOOGLE_PLACE_ID = g.GMAP:google_place_id::VARCHAR
FROM GMAP_RESULTS g
WHERE d.AGENCY_ID = g.AGENCY_ID AND d.SITE = g.SITE
  AND g.GMAP:status::VARCHAR = 'OK';

-- Fill the cache. MERGE ... WHEN NOT MATCHED = only insert places we do not know yet,
-- so re-running the pipeline next month does not duplicate rows.
-- QUALIFY keeps one row per Place ID when several dealers point to the same place (multi-site dealers).
MERGE INTO DEALER_GOOGLE_MAP t
USING (
    SELECT GMAP:google_place_id::VARCHAR AS GOOGLE_PLACE_ID,
           GMAP:name::VARCHAR            AS AI_AGENCY_NAME,
           GMAP                          AS GOOGLE_JSON
    FROM GMAP_RESULTS
    WHERE GMAP:status::VARCHAR = 'OK'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY GOOGLE_PLACE_ID ORDER BY AGENCY_ID) = 1
) s
ON t.GOOGLE_PLACE_ID = s.GOOGLE_PLACE_ID
WHEN NOT MATCHED THEN INSERT (GOOGLE_PLACE_ID, AI_AGENCY_NAME, GOOGLE_JSON)
VALUES (s.GOOGLE_PLACE_ID, s.AI_AGENCY_NAME, s.GOOGLE_JSON);

-- Content of the Google Maps cache.
SELECT GOOGLE_PLACE_ID, AI_AGENCY_NAME,
       GOOGLE_JSON:formatted_address::VARCHAR AS ADDRESS,
       GOOGLE_JSON:phone::VARCHAR AS PHONE
FROM DEALER_GOOGLE_MAP;
