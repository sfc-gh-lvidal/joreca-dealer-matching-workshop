# Block 0 — Setup + Briefing

## Goal
Get everyone connected, create the workshop environment, load the real sample, and present the pipeline.

## 0. (Admin, once) Account prerequisites
The participant who holds `ACCOUNTADMIN` runs `admin_prereqs.sql` once, before the session (~1 min).
Edit the `GRANT ROLE WORKSHOP_DEV TO USER ...` lines first (one per developer).

```bash
snow sql -f 00-setup/admin_prereqs.sql --role ACCOUNTADMIN
```

It creates everything that needs `ACCOUNTADMIN`, then hands it to a single workshop role:

| Object | Who creates it | Used by `WORKSHOP_DEV` as |
|--------|----------------|---------------------------|
| Role `WORKSHOP_DEV`, granted to each dev | admin | the role for the whole workshop |
| `WORKSHOP_WH`, `WORKSHOP_DB` | admin | USAGE on the warehouse, OWNER of the database |
| Network rules + secrets (placeholder keys) | admin | OWNER: devs paste the real keys with `ALTER SECRET` |
| `GOOGLE_MAPS_EAI`, `GEMINI_EAI`, `GITHUB_WORKSHOP_API` | admin | USAGE |
| Stage, tables, UDFs, views | developers | OWNER |

From then on, every developer works with `WORKSHOP_DEV` only:
- Snow CLI: the scripts start with `USE ROLE WORKSHOP_DEV` (or add `--role WORKSHOP_DEV`)
- Snowsight: user menu (bottom left) > *Switch role* > `WORKSHOP_DEV`

### Open the repo in Snowsight (Git workspace)
With the role `WORKSHOP_DEV` selected:
1. **Projects > Workspaces > From Git repository**
2. Repository URL: `https://github.com/sfc-gh-lvidal/joreca-dealer-matching-workshop`
3. API integration: `GITHUB_WORKSHOP_API`
4. Authentication: **Public repository** > *Create*

Each workspace belongs to its user, so files don't collide. It is read-only towards GitHub (pull only, no push).
The Snowflake objects (`WORKSHOP_DB`) are shared: work in pairs, one pair runs the `CREATE OR REPLACE` statements at a time.

## 1. Test the Snow CLI connection
```bash
snow connection test
snow sql -q "SELECT CURRENT_ACCOUNT_NAME(), CURRENT_USER(), CURRENT_ROLE()"
```
Check the account name: it must be the Joreca account.

## 2. Create the environment, upload the files, load DEALERS
`create_workshop_db.sql` uses `WORKSHOP_DB` / `WORKSHOP_WH` (created by the admin) and creates the `WORKSHOP_STAGE` stage and the 3 tables.

```bash
# 1. create the stage (first statements of the file)
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
