-- ----------------------------------------------------------------------
-- Block 1 - Collect: explore the DEALERS table
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------
USE ROLE WORKSHOP_DEV; USE DATABASE WORKSHOP_DB; USE SCHEMA PUBLIC; USE WAREHOUSE WORKSHOP_WH;

-- Raw crawl data: look at name and address quality.
SELECT * FROM DEALERS LIMIT 10;

-- Which marketplaces the sample comes from.
SELECT SITE, COUNT(*) AS N FROM DEALERS GROUP BY SITE ORDER BY N DESC;

-- How many dealers already have a SIRET from the crawl (the rest must be found by Gemini).
SELECT COUNT(*) AS TOTAL,
       COUNT(SIRET) AS WITH_SIRET,
       ROUND(COUNT(SIRET) / COUNT(*) * 100, 1) AS SIRET_PCT
FROM DEALERS;

-- Typical issues: country prefix in the address (FR-74100), underscores in city names, missing zip.
SELECT AGENCY_NAME, ADDRESS, CITY, ZIP_CODE
FROM DEALERS
WHERE ADDRESS ILIKE 'FR-%' OR CITY LIKE '%\\_%' OR ZIP_CODE IS NULL
LIMIT 20;
