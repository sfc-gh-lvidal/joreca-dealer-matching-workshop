# Block 0 — Setup + Briefing

## Goal

Get everyone connected, create the workshop database, load the real sample data, and present the pipeline architecture.

## Step 1: Test Snow CLI

```bash
snow connection test
snow sql -q "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE()"
```

## Step 2: Create the workshop environment

```bash
snow sql -f create_workshop_db.sql
```

## Step 3: Load the data

Upload the CSV to the stage, then copy into the DEALERS table:

```bash
snow stage copy data/dealers_sample.csv @WORKSHOP_DB.PUBLIC.WORKSHOP_STAGE --database WORKSHOP_DB --schema PUBLIC
snow sql -q "CALL WORKSHOP_DB.PUBLIC.LOAD_DEALERS()"
```

Or run `create_workshop_db.sql` block by block in a Notebook.

## Step 4: Verify

```bash
snow sql -q "SELECT COUNT(*) FROM WORKSHOP_DB.PUBLIC.DEALERS"
-- Expected: 200
```

## Briefing

Present the pipeline (9 steps), zoom on steps 1–4 that we cover today. Show the data architecture diagram. Explain why we're doing this: **replace the Linux server + MariaDB + batch files with Snowflake**.
