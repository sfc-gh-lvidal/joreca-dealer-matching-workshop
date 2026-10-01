# [OPTIONAL] Change Tracking — AGENCY_CHANGE_LOG

## Goal

Implement step 8 of the pipeline: detect month-over-month changes in dealer and concession data, and log them as NEW / REMOVED / MODIFIED entries.

## How it works (from Joreca doc)

Two sources are tracked independently:

### CONCESSION source (via snapshots)
- Compare `CONCESSION_SNAPSHOT` for period N vs period N-1, keyed by JORECA_ID
- NEW: JORECA_ID exists in N but not N-1
- REMOVED: JORECA_ID exists in N-1 but not N
- MODIFIED: same JORECA_ID, different field values → one row per changed field

### DEALER source (direct diff)
- Compare `DEALERS` for period N vs N-1, keyed by (AGENCY_ID, SITE)
- Same NEW / REMOVED / MODIFIED logic
- Also tracks JORECA_ID changes (when a dealer gets matched/re-matched)

## Schema

```sql
CREATE TABLE AGENCY_CHANGE_LOG (
    PERIOD          VARCHAR,        -- e.g. '2026_08'
    SOURCE          VARCHAR,        -- 'CONCESSION' or 'DEALER'
    CHANGE_TYPE     VARCHAR,        -- 'NEW', 'REMOVED', 'MODIFIED'
    ENTITY_KEY      VARCHAR,        -- JORECA_ID (concession) or AGENCY_ID||SITE (dealer)
    FIELD           VARCHAR,        -- changed field name (NULL for NEW/REMOVED)
    OLD_VALUE       VARCHAR,
    NEW_VALUE       VARCHAR,
    LOGGED_AT       TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
```

## Implementation with Snowflake Streams

Instead of manual snapshot diffs, consider using **Snowflake Streams** on the DEALERS and CONCESSION tables to capture changes automatically. A stream tracks inserts, updates, and deletes since the last consumption.

```sql
CREATE STREAM dealers_changes ON TABLE DEALERS;
-- Then process the stream with a Task to populate AGENCY_CHANGE_LOG
```
