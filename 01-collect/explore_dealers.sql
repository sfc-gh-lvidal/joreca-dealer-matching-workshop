----------------------------------------------------------------------
-- Explore the DEALERS table — data quality and patterns
----------------------------------------------------------------------

USE DATABASE WORKSHOP_DB;
USE SCHEMA PUBLIC;

-- 1. Overview
SELECT COUNT(*) AS TOTAL_DEALERS FROM DEALERS;

SELECT * FROM DEALERS LIMIT 10;

-- 2. Which marketplace sites are represented?
SELECT SITE, COUNT(*) AS DEALER_COUNT
FROM DEALERS
GROUP BY SITE
ORDER BY DEALER_COUNT DESC;

-- 3. SIRET coverage — how many dealers have a SIRET?
SELECT
    COUNT(*) AS TOTAL,
    SUM(CASE WHEN SIRET != '' AND SIRET IS NOT NULL THEN 1 ELSE 0 END) AS WITH_SIRET,
    TOTAL - WITH_SIRET AS WITHOUT_SIRET,
    ROUND(WITH_SIRET / TOTAL * 100, 1) AS SIRET_COVERAGE_PCT
FROM DEALERS;

-- 4. Address quality — look at the inconsistencies
SELECT AGENCY_NAME, ADDRESS, CITY, ZIP_CODE
FROM DEALERS
WHERE ADDRESS LIKE 'FR-%'    -- addresses with country prefix embedded
   OR CITY LIKE '%\_%'       -- cities with underscores
   OR ZIP_CODE = ''
LIMIT 20;

-- 5. Name variations — same dealer, different names across sites?
SELECT AGENCY_NAME, COUNT(DISTINCT SITE) AS SITE_COUNT, ARRAY_AGG(DISTINCT SITE) AS SITES
FROM DEALERS
GROUP BY AGENCY_NAME
HAVING SITE_COUNT > 1
ORDER BY SITE_COUNT DESC
LIMIT 10;

-- 6. Sample of what we need to enrich
SELECT AGENCY_ID, SITE, AGENCY_NAME, ADDRESS, CITY, ZIP_CODE
FROM DEALERS
WHERE SIRET = '' OR SIRET IS NULL
LIMIT 15;
