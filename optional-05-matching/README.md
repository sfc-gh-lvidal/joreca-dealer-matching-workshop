# [OPTIONAL] Step 5-6 — Matching: Link Dealers to Concessions

## Goal

Implement the multi-level matching system that links each enriched dealer to a canonical CONCESSION entry via JORECA_ID.

## Matching levels (from Joreca's POC)

The production system uses 20+ matching levels, from most reliable to most fuzzy:

| Level | Criteria | % of matches |
|-------|----------|-------------|
| 1 | GOOGLE_PLACE_ID exact match | ~42% |
| 2 | AGENCY_NAME + SIRET + business domain + country | ~11% |
| 3 | AGENCY_NAME + SIRET + country | <1% |
| 4 | SIRET + country | ~3% |
| 5 | SIRET + AI_SIRET + country | ~2% |
| 6 | AGENCY_NAME + registration number + domain + address | ~2% |
| 7+ | Various combinations of name, address, phone, website | remaining |

## Implementation approach

```sql
-- Create the CONCESSION table (simplified for workshop)
CREATE TABLE IF NOT EXISTS CONCESSION (
    ID          NUMBER AUTOINCREMENT PRIMARY KEY,
    JORECA_ID   VARCHAR UNIQUE,
    AGENCY_NAME VARCHAR,
    GOOGLE_PLACE_ID VARCHAR,
    ADDRESS     VARCHAR,
    CITY        VARCHAR,
    ZIP_CODE    VARCHAR,
    SIRET       VARCHAR
);

-- Level 1: Match by GOOGLE_PLACE_ID
UPDATE DEALER_ADDRESS_STANDARD das
SET JORECA_ID = c.JORECA_ID
FROM CONCESSION c
WHERE das.GOOGLE_PLACE_ID = c.GOOGLE_PLACE_ID
  AND das.JORECA_ID IS NULL;

-- Level 2: Match by AGENCY_NAME + SIRET
UPDATE DEALER_ADDRESS_STANDARD das
SET JORECA_ID = c.JORECA_ID
FROM CONCESSION c
JOIN DEALERS d ON das.AGENCY_ID = d.AGENCY_ID AND das.SITE = d.SITE
WHERE UPPER(d.AGENCY_NAME) = UPPER(c.AGENCY_NAME)
  AND d.SIRET = c.SIRET
  AND d.SIRET != ''
  AND das.JORECA_ID IS NULL;

-- For unmatched dealers: create new CONCESSION entries
-- (This is step 6 in the pipeline)
```

## Notes

- The EVOL levels use AI-standardized names (from Gemini) instead of raw names
- In production, matching is run level by level, stopping at the first match
- New concessions are created only for dealers that don't match any existing entry
