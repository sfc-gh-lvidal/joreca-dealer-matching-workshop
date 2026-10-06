-- ----------------------------------------------------------------------
-- Block 4 - Resolve: final Google Place ID + enriched view + cleanup
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------
USE ROLE WORKSHOP_DEV; USE DATABASE WORKSHOP_DB; USE SCHEMA PUBLIC; USE WAREHOUSE WORKSHOP_WH;

-- Step 4 (Resolve): decide which Google Place ID is the right one for each dealer.
-- Simplified rule for the workshop: keep it only if Gemini is confident (>= 0.7)
-- AND the postal code found by Gemini appears in the Google Maps address.
-- Production adds a second Gemini pass for ambiguous cases.
-- Keep the Google Place ID found in step 2 only if Gemini found a confident match
-- whose postal code is the same as the Google Maps address.
UPDATE DEALER_ADDRESS_STANDARD das
SET GOOGLE_PLACE_ID = d.GOOGLE_PLACE_ID
FROM DEALERS d
JOIN DEALER_GOOGLE_MAP g ON d.GOOGLE_PLACE_ID = g.GOOGLE_PLACE_ID
WHERE das.AGENCY_ID = d.AGENCY_ID AND das.SITE = d.SITE
  AND das.AI_JSON:potential_matches[0]:match_confidence_score::FLOAT >= 0.7
  AND CONTAINS(g.GOOGLE_JSON:formatted_address::VARCHAR,
               das.AI_JSON:potential_matches[0]:cp::VARCHAR);

-- One view that joins the 3 tables: raw crawl vs Gemini vs Google Maps, side by side.
CREATE OR REPLACE VIEW DEALERS_ENRICHED AS
SELECT d.AGENCY_ID, d.SITE,
       d.AGENCY_NAME                                                   AS RAW_NAME,
       das.AI_JSON:potential_matches[0]:found_agency_name::VARCHAR     AS AI_AGENCY_NAME,
       CONCAT_WS(', ', d.ADDRESS, d.ZIP_CODE, d.CITY)                  AS RAW_ADDRESS,
       das.AI_STANDARD_ADDRESS,
       d.SIRET                                                         AS RAW_SIRET,
       das.AI_JSON:potential_matches[0]:establishment_level_number::VARCHAR AS AI_SIRET,
       das.GOOGLE_PLACE_ID                                             AS RESOLVED_PLACE_ID,
       g.GOOGLE_JSON:formatted_address::VARCHAR                        AS GOOGLE_ADDRESS,
       g.GOOGLE_JSON:latitude::FLOAT                                   AS LATITUDE,
       g.GOOGLE_JSON:longitude::FLOAT                                  AS LONGITUDE,
       das.AI_JSON:potential_matches[0]:match_confidence_score::FLOAT  AS CONFIDENCE
FROM DEALERS d
JOIN DEALER_ADDRESS_STANDARD das ON d.AGENCY_ID = das.AGENCY_ID AND d.SITE = das.SITE
LEFT JOIN DEALER_GOOGLE_MAP g ON das.GOOGLE_PLACE_ID = g.GOOGLE_PLACE_ID;

-- Compare RAW_* columns with the enriched ones.
SELECT * FROM DEALERS_ENRICHED ORDER BY CONFIDENCE DESC;

-- How many dealers were standardized and resolved.
SELECT COUNT(*) AS PROCESSED,
       COUNT(AI_STANDARD_ADDRESS) AS STANDARDIZED,
       COUNT(RESOLVED_PLACE_ID) AS PLACE_ID_RESOLVED
FROM DEALERS_ENRICHED;

-- Cleanup after the workshop: see the CLEANUP section at the end of 00-setup/admin_prereqs.sql
-- (ACCOUNTADMIN drops the 3 integrations, WORKSHOP_DB, WORKSHOP_WH and the WORKSHOP_DEV role).
SELECT 'cleanup cell (commented out)' AS INFO;
