# Dealer Matching on Snowflake — Hands-on Workshop

## Overview

This workshop walks you through migrating Joreca's **dealer matching pipeline** into Snowflake — from raw crawled marketplace listings to enriched, standardized dealer records.

Today, this pipeline runs on a Linux server with Python scripts, MariaDB, and JSON files sent to Google Maps and Gemini APIs. By the end of this workshop, you'll have built the core of this pipeline inside Snowflake, with no external server needed.

**Duration:** 2h – 2h30  
**Audience:** Developers familiar with Python and SQL  
**Tools:** Snow CLI, Snowflake Notebooks, VS Code (optional)

---

## The Pipeline

Joreca's dealer matching pipeline has 9 steps. In this workshop, we focus on **steps 1–4** — the core data flow that is currently blocked by the Linux server dependency.

| Step | Name | What it does | Workshop? |
|------|------|-------------|-----------|
| 0 | Reset | Archive old concessions | - |
| 1 | **Collect** | Build DEALERS table from marketplace crawl | **YES** |
| 2 | **Locate** | Google Maps: find Place ID, fetch details | **YES** |
| 3 | **Enrich** | Gemini Batch API: address standardization + agency search | **YES** |
| 4 | **Resolve** | Choose final Google Place ID; second Gemini pass | **YES** |
| 5 | Consolidate | Write to DEALERS + CONCESSION, deduplicate | optional |
| 6 | Match | Link each dealer to a CONCESSION (JORECA_ID) | optional |
| 7 | Sync | Update listing counts per concession | optional |
| 8 | Track | Log month-over-month changes (AGENCY_CHANGE_LOG) | optional |

---

## Data Architecture

The tables we create during the workshop use the **same names as the target production architecture**:

```
DEALERS (input crawl, 1000 rows)
    │
    ├───► Step 2: Google Maps API (Find Place + Place Details)
    │         └──► DEALER_GOOGLE_MAP (cache: GOOGLE_PLACE_ID → normalized name, address, JSON)
    │
    └───► Step 3: Gemini API + Google Search (Joreca production prompt, prompts/gemini_search_agency.txt)
              └──► DEALER_ADDRESS_STANDARD (per-period: AI_JSON, standardized address, resolved GOOGLE_PLACE_ID)
                       │
                       └───► Step 4: Resolve — choose final GOOGLE_PLACE_ID
```

### Table: DEALERS (input — step 1)

Source-site dealers for the current period. One row per dealer per marketplace site.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `AGENCY_ID` | VARCHAR | Dealer ID on the source site (PK with SITE) | `AUDEXIA-SAS-AUDI` |
| `SITE` | VARCHAR | Marketplace source (PK with AGENCY_ID) | `Audi.fr`, `autoscout` |
| `AGENCY_NAME` | VARCHAR | Dealer name as scraped | `Audexia SAS Audi` |
| `ADDRESS` | VARCHAR | Address as scraped | `1461 Route d Orleans` |
| `CITY` | VARCHAR | City | `Saint-Doulchard` |
| `ZIP_CODE` | VARCHAR | Postal code | `18230` |
| `SIRET` | VARCHAR | SIRET number (often empty) | `45017786000027` |
| `MINISITE_URL` | VARCHAR | Dealer's minisite URL | `https://...` |
| `GOOGLE_PLACE_ID` | VARCHAR | Filled in step 2 (Locate) | `ChIJ...` |
| `JORECA_ID` | VARCHAR | Filled in step 6 (Match, optional module) | `223235` |

### Table: DEALER_GOOGLE_MAP (cache — step 2)

Google Maps enrichment cache. One row per unique GOOGLE_PLACE_ID. Rolling table (reused across periods).

| Column | Type | Description |
|--------|------|-------------|
| `GOOGLE_PLACE_ID` | VARCHAR | Google Maps Place ID (PK) |
| `AI_AGENCY_NAME` | VARCHAR | Business name from Google Maps |
| `GOOGLE_JSON` | VARIANT | Full Place Details response |

### Table: DEALER_ADDRESS_STANDARD (workspace — step 3)

Address standardization and Place ID resolution. Per-period table, one row per (AGENCY_ID, SITE).

| Column | Type | Description |
|--------|------|-------------|
| `AGENCY_ID` | VARCHAR | FK to DEALERS |
| `SITE` | VARCHAR | FK to DEALERS |
| `GOOGLE_PLACE_ID` | VARCHAR | Resolved Place ID |
| `JORECA_ID` | VARCHAR | Matched concession ID (set in step 6) |
| `IS_REUSED` | BOOLEAN | Whether result was reused from previous period |
| `AI_JSON` | VARIANT | Full Gemini response (format defined by the prompt) + token usage in `_usage` |
| `AI_STANDARD_ADDRESS` | VARCHAR | Gemini-standardized address |

---

## Agenda

| Time | Block | Duration | What we build |
|------|-------|----------|---------------|
| 15:00 | **Setup + Briefing** | 20 min | Snow CLI connection. Create `WORKSHOP_DB`. Present the pipeline. Load `DEALERS` from stage. |
| 15:20 | **Step 1: Collect** | 15 min | Explore `DEALERS`: data quality, missing SIRETs, inconsistent names. Write exploration queries. |
| 15:35 | **Step 2: Locate (Google Maps)** | 35 min | Configure EAI for Google Maps. Write UDF `FIND_GOOGLE_PLACE()`. Populate `DEALERS.GOOGLE_PLACE_ID` and `DEALER_GOOGLE_MAP`. |
| 16:10 | **Step 3: Enrich (Gemini)** | 35 min | Gemini Batch API from Snowflake: `SUBMIT_GEMINI_BATCH` (JSONL + batch job, production prompt), coffee break, `COLLECT_GEMINI_BATCH` into `DEALER_ADDRESS_STANDARD`. Measure tokens per dealer. |
| 16:45 | **Step 4: Resolve + Wrap-up** | 15–25 min | Resolve final GOOGLE_PLACE_ID. Compare with prod results. Discuss next steps. |

**If time permits:** run Cortex AI on the same data to compare with Gemini.

---

## Prerequisites

**Install:**
- Snow CLI: see [installation guide](https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation/installation) — macOS: `brew tap snowflakedb/snowflake-cli && brew trust --cask snowflakedb/snowflake-cli/snowflake-cli && brew install --cask snowflake-cli`; Windows / Linux: native installer; any OS: `uv tool install snowflake-cli` or `pipx install snowflake-cli`
- Python 3.10+ (only if you install Snow CLI as a Python tool)
- VS Code + Snowflake extension (recommended)
- Git

**Prepare:**
- Snowflake user with access to the Joreca account
- Test connection: `snow connection test`
- Google Maps API key, with the **Places API** enabled on the Google Cloud project
- Gemini API key (model `gemini-2.5-flash`, Google Search grounding)

**Optional reading:**
- [Snowpark Python Developer Guide](https://docs.snowflake.com/en/developer-guide/snowpark/python/index)
- [Snow CLI Overview](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index)
- [External Access Integrations](https://docs.snowflake.com/en/developer-guide/external-network-access/external-network-access-overview)

---

## Repo Structure

```
workshop/
├── README.md                          ← You are here
├── data/
│   └── dealers_sample.csv             # 1000 real crawled dealers (clean random sample of the POC comparison file, all sites)
├── prompts/
│   └── gemini_search_agency.txt       # Joreca production Gemini prompt (loaded by the UDF from the stage)
├── 00-setup/                          # Create WORKSHOP_DB, load data
├── 01-collect/                        # Explore DEALERS
├── 02-locate-google-maps/             # Google Maps EAI + UDF → DEALER_GOOGLE_MAP
├── 03-enrich-gemini/                  # Gemini Batch API (2 procedures) → DEALER_ADDRESS_STANDARD
├── 04-resolve/                        # Final resolution + comparison
├── 05-automate/                       # Stored procedures + task graph: steps 2-4 end to end
├── optional-05-matching/              # Matching multi-niveaux → CONCESSION
├── optional-06-cortex-ai/             # Cortex AI vs Gemini comparison
├── optional-07-data-quality/          # DMFs on enriched data
├── optional-08-change-tracking/       # AGENCY_CHANGE_LOG
├── optional-09-scheduling/            # Snowflake Tasks for monthly runs
├── workshop_notebook.ipynb            # Same steps as the SQL files, to run in a Snowflake Workspace
├── prerequisites_email.md
└── methodology/
    └── workshop-template.md
```

---

## Three ways to run the workshop

**Snowflake Notebook** — create a Git workspace from this repo (admin runs `00-setup/admin_prereqs.sql` once, then select the role `WORKSHOP_DEV`, see `00-setup/README.md`), open `workshop_notebook.ipynb` and run the cells in order.

**Snow CLI** — run the SQL files from your terminal, in order:

```bash
snow sql -f 00-setup/admin_prereqs.sql --role ACCOUNTADMIN   # once, by the admin
snow stage copy data/dealers_sample.csv @WORKSHOP_DB.PUBLIC.WORKSHOP_STAGE      # after 00-setup created the stage
snow stage copy prompts/gemini_search_agency.txt @WORKSHOP_DB.PUBLIC.WORKSHOP_STAGE/prompts
snow sql -f 00-setup/create_workshop_db.sql
snow sql -f 01-collect/explore_dealers.sql
snow sql -f 02-locate-google-maps/setup_eai_google.sql      # paste your key first (ALTER SECRET)
snow sql -f 02-locate-google-maps/google_maps_udf.sql
snow sql -f 03-enrich-gemini/setup_eai_gemini.sql           # paste your key first (ALTER SECRET)
snow sql -f 03-enrich-gemini/gemini_batch.sql             # then re-run: CALL COLLECT_GEMINI_BATCH(NULL);
snow sql -f 04-resolve/resolve_and_compare.sql
snow sql -f 05-automate/automate_pipeline.sql             # procedures + task graph, EXECUTE TASK
```

**VS Code** — clone the repo and run the SQL files with the Snowflake extension (details below).

All paths run the exact same code. The number of dealers sent to the APIs is `SAMPLE_SIZE` in the notebook, `LIMIT 10` in the SQL files.


### Run in VS Code

The extension is only a client: every statement and every UDF runs **in Snowflake**, nothing runs on your laptop.

**1. Clone and open the repo**
```bash
git clone https://github.com/sfc-gh-lvidal/joreca-dealer-matching-workshop.git
code joreca-dealer-matching-workshop
```

**2. Install the extension** — Extensions › search `Snowflake` › install the one with the Snowflake verified badge.

**3. Sign in**
- Click the **Snowflake icon** (snowflake) in the Activity Bar.
- The extension reads the same connections file as Snow CLI (`~/.snowflake/config.toml` or `connections.toml`): your `joreca` connection appears in the **Account** pane › select it › **Sign in**.
- No connection listed? Enter the account identifier (`<orgname>-<accountname>`), pick the auth method (password / SSO / key pair), sign in. Or point *Settings › Snowflake: Connections Config File* to `~/.snowflake/config.toml` and restart VS Code.
- SSO opens a browser page: authenticate, then come back to VS Code.

**4. Check the connection** (the equivalent of `snow connection test`)
- The sidebar shows your account, role, **Object Explorer** (with `WORKSHOP_DB`) and **Query History**.
- In the Account pane, select role **`WORKSHOP_DEV`** and warehouse **`WORKSHOP_WH`**.
- Run in any `.sql` file: `SELECT CURRENT_ACCOUNT_NAME(), CURRENT_USER(), CURRENT_ROLE();` — expected: the Joreca account, your user, `WORKSHOP_DEV`.

**5. Upload the files to the stage** (block 0), either:
- in the VS Code terminal: the two `snow stage copy` commands above, or
- in the Object Explorer: `WORKSHOP_DB › PUBLIC › Stages › WORKSHOP_STAGE` › **Upload**.

**6. Run the scripts in order** (`00-setup` → `04-resolve`)
- One statement: cursor on it › **Cmd+Enter** (Ctrl+Enter on Windows) or *Execute* above the statement.
- Whole file: **Snowflake: Execute All Statements**.
- Results appear in the Snowflake pane; past queries in Query History (also visible in Snowsight › Monitoring › Query History).

**Watch out**
- `workshop_notebook.ipynb` does not run in VS Code: its `%%sql` cells are Snowflake Workspace notebook cells. Use the `.sql` files.
- `setup_eai_*.sql`: paste your key before running, or skip the `ALTER SECRET` if the key is already set. Don't *Execute All* blindly.
- Several connections? The one selected in the Account pane is used.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `FIND_GOOGLE_PLACE` returns `status: ERROR`, `REQUEST_DENIED` | Wrong key, or Places API not enabled on the Google Cloud project |
| `SUBMIT_GEMINI_BATCH` / `SEARCH_AGENCY` returns `HTTP 400: API key not valid` | Wrong Gemini key in the secret: re-run `setup_eai_gemini.sql` |
| Batch stays `PENDING` / `RUNNING` | Normal: asynchronous. Re-run `CALL COLLECT_GEMINI_BATCH(NULL);` a few minutes later |
| `SUBMIT_GEMINI_BATCH` returns `NOTHING_TO_DO` | Every dealer already has a result or is in a pending job |
| `Database 'WORKSHOP_DB' does not exist` | Wrong connection / account: check `snow connection list` |
| `COPY INTO` loads 0 rows | The CSV was not uploaded: run the `snow stage copy` command, then `LIST @WORKSHOP_STAGE` |
| `IMPORTS` error on `SUBMIT_GEMINI_BATCH` / `SEARCH_AGENCY` | The prompt file is not on the stage at `@WORKSHOP_STAGE/prompts/` |
| A key appears in results | It should not: keys are read from SECRETs and sent in headers / never returned in errors |
