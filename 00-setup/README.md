# Block 0 — Setup + Briefing

## Goal
Get everyone connected, create the workshop environment, load the real sample, and present the pipeline.

## 1. Test the Snow CLI connection
```bash
snow connection test
snow sql -q "SELECT CURRENT_ACCOUNT_NAME(), CURRENT_USER(), CURRENT_ROLE()"
```
Check the account name: it must be the Joreca account.

## 2. Create the environment, upload the files, load DEALERS
`create_workshop_db.sql` creates `WORKSHOP_DB`, the `WORKSHOP_WH` warehouse, the `WORKSHOP_STAGE` stage and the 3 tables.

```bash
# 1. create database / warehouse / stage (first statements of the file)
snow sql -f 00-setup/create_workshop_db.sql
# 2. upload the data and the Gemini prompt to the stage
snow stage copy data/dealers_sample.csv @WORKSHOP_DB.PUBLIC.WORKSHOP_STAGE
snow stage copy prompts/gemini_search_agency.txt @WORKSHOP_DB.PUBLIC.WORKSHOP_STAGE/prompts
# 3. re-run the file: the COPY INTO now finds the CSV
snow sql -f 00-setup/create_workshop_db.sql
```

Expected at the end: `DEALERS = 200`, `DEALER_GOOGLE_MAP = 0`, `DEALER_ADDRESS_STANDARD = 0`.

## Briefing (whiteboard)
- The 9 pipeline steps, focus on 1-4 today
- The target tables: `DEALERS`, `DEALER_GOOGLE_MAP`, `DEALER_ADDRESS_STANDARD` (same names as production)
- What replaces what: MariaDB -> tables, Linux server + cron -> UDFs / Tasks, local files -> stage, batch JSON files -> one SQL query
