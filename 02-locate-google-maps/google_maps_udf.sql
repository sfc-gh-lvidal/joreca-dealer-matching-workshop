----------------------------------------------------------------------
-- Google Maps UDF: Find Place + Place Details → DEALER_GOOGLE_MAP
----------------------------------------------------------------------

USE ROLE SYSADMIN;
USE DATABASE WORKSHOP_DB;
USE SCHEMA PUBLIC;
USE WAREHOUSE WORKSHOP_WH;

-- 1. Create the UDF
CREATE OR REPLACE FUNCTION find_google_place(
    agency_name VARCHAR,
    address VARCHAR,
    city VARCHAR,
    zip_code VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('requests')
HANDLER = 'find_place'
EXTERNAL_ACCESS_INTEGRATIONS = (google_maps_eai)
SECRETS = ('gmap_key' = google_maps_api_key)
AS
$$
import _snowflake
import requests
import json

def find_place(agency_name: str, address: str, city: str, zip_code: str) -> dict:
    api_key = _snowflake.get_generic_secret_string('gmap_key')

    # Build search query from available fields
    query_parts = [p for p in [agency_name, address, city, zip_code] if p]
    search_query = ', '.join(query_parts)

    # --- Step 1: Find Place (text search) ---
    find_url = "https://maps.googleapis.com/maps/api/place/findplacefromtext/json"
    find_params = {
        "input": search_query,
        "inputtype": "textquery",
        "fields": "place_id,name,formatted_address,geometry",
        "language": "fr",
        "key": api_key
    }

    try:
        find_resp = requests.get(find_url, params=find_params, timeout=15)
        find_resp.raise_for_status()
        find_data = find_resp.json()

        if find_data.get("status") != "OK" or not find_data.get("candidates"):
            return {
                "status": "NOT_FOUND",
                "search_query": search_query,
                "google_place_id": None,
                "details": None
            }

        candidate = find_data["candidates"][0]
        place_id = candidate.get("place_id")

        if not place_id:
            return {
                "status": "NO_PLACE_ID",
                "search_query": search_query,
                "google_place_id": None,
                "details": candidate
            }

        # --- Step 2: Place Details ---
        details_url = "https://maps.googleapis.com/maps/api/place/details/json"
        details_params = {
            "place_id": place_id,
            "fields": "place_id,name,formatted_address,formatted_phone_number,website,geometry,business_status,types,address_components",
            "language": "fr",
            "key": api_key
        }

        details_resp = requests.get(details_url, params=details_params, timeout=15)
        details_resp.raise_for_status()
        details_data = details_resp.json()

        result = details_data.get("result", {})

        return {
            "status": "OK",
            "search_query": search_query,
            "google_place_id": place_id,
            "name": result.get("name"),
            "formatted_address": result.get("formatted_address"),
            "phone": result.get("formatted_phone_number"),
            "website": result.get("website"),
            "latitude": result.get("geometry", {}).get("location", {}).get("lat"),
            "longitude": result.get("geometry", {}).get("location", {}).get("lng"),
            "business_status": result.get("business_status"),
            "types": result.get("types", []),
            "address_components": result.get("address_components", []),
            "full_response": result
        }

    except Exception as e:
        return {
            "status": "ERROR",
            "search_query": search_query,
            "error": str(e),
            "google_place_id": None
        }
$$;

-- 2. Test on 3 rows
SELECT
    d.AGENCY_ID,
    d.SITE,
    d.AGENCY_NAME,
    find_google_place(d.AGENCY_NAME, d.ADDRESS, d.CITY, d.ZIP_CODE) AS GMAP_RESULT
FROM DEALERS d
LIMIT 3;

-- 3. Populate DEALER_GOOGLE_MAP from all dealers
--    (In production, you'd check for existing entries to avoid re-fetching)
INSERT INTO DEALER_GOOGLE_MAP (GOOGLE_PLACE_ID, AI_AGENCY_NAME, GOOGLE_JSON)
SELECT DISTINCT
    gmap.VALUE:"google_place_id"::VARCHAR AS GOOGLE_PLACE_ID,
    gmap.VALUE:"name"::VARCHAR AS AI_AGENCY_NAME,
    gmap.VALUE AS GOOGLE_JSON
FROM DEALERS d,
LATERAL (
    SELECT find_google_place(d.AGENCY_NAME, d.ADDRESS, d.CITY, d.ZIP_CODE) AS VALUE
) gmap
WHERE gmap.VALUE:"google_place_id" IS NOT NULL
  AND gmap.VALUE:"status"::VARCHAR = 'OK'
  AND NOT EXISTS (
      SELECT 1 FROM DEALER_GOOGLE_MAP existing
      WHERE existing.GOOGLE_PLACE_ID = gmap.VALUE:"google_place_id"::VARCHAR
  );

-- 4. Check results
SELECT COUNT(*) AS PLACES_FOUND FROM DEALER_GOOGLE_MAP;

SELECT GOOGLE_PLACE_ID, AI_AGENCY_NAME,
       GOOGLE_JSON:"formatted_address"::VARCHAR AS ADDRESS,
       GOOGLE_JSON:"phone"::VARCHAR AS PHONE
FROM DEALER_GOOGLE_MAP
LIMIT 10;
