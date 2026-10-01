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
| 3 | **Enrich** | Gemini AI: address standardization + agency search | **YES** |
| 4 | **Resolve** | Choose final Google Place ID; second Gemini pass | **YES** |
| 5 | Consolidate | Write to DEALERS + CONCESSION, deduplicate | optional |
| 6 | Match | Link each dealer to a CONCESSION (JORECA_ID) | optional |
| 7 | Sync | Update listing counts per concession | optional |
| 8 | Track | Log month-over-month changes (AGENCY_CHANGE_LOG) | optional |

---

## Data Architecture

The tables we create during the workshop use the **same names as the target production architecture**:

```
DEALERS (input crawl, ~200 rows)
    │
    ├───► Step 2: Google Maps API (Find Place + Place Details)
    │         └──► DEALER_GOOGLE_MAP (cache: GOOGLE_PLACE_ID → normalized name, address, JSON)
    │
    └───► Step 3: Gemini API (address standardization, agency verification)
              │   uses DEALER_GOOGLE_MAP data as context
              └──► DEALER_ADDRESS_STANDARD (per-period: standardized address, resolved GOOGLE_PLACE_ID)
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
| `AI_JSON` | VARIANT | Full Gemini response |
| `AI_STANDARD_ADDRESS` | VARCHAR | Gemini-standardized address |

---

## Agenda

| Time | Block | Duration | What we build |
|------|-------|----------|---------------|
| 15:00 | **Setup + Briefing** | 20 min | Snow CLI connection. Create `WORKSHOP_DB`. Present the pipeline. Load `DEALERS` from stage. |
| 15:20 | **Step 1: Collect** | 15 min | Explore `DEALERS`: data quality, missing SIRETs, inconsistent names. Write exploration queries. |
| 15:35 | **Step 2: Locate (Google Maps)** | 35 min | Configure EAI for Google Maps. Write UDF `find_google_place()`. Populate `DEALER_GOOGLE_MAP`. |
| 16:10 | **Step 3: Enrich (Gemini)** | 35 min | Configure EAI for Gemini. Write UDF `standardize_address()`. Populate `DEALER_ADDRESS_STANDARD`. |
| 16:45 | **Step 4: Resolve + Wrap-up** | 15–25 min | Resolve final GOOGLE_PLACE_ID. Compare with prod results. Discuss next steps. |

**If time permits:** run Cortex AI on the same data to compare with Gemini.

---

## Prerequisites

**Install:**
- Snow CLI: `pip install snowflake-cli-labs` (or `brew install snowflake-cli`)
- Python 3.8+
- VS Code + Snowflake extension (recommended)
- Git

**Prepare:**
- Snowflake user with access to the Joreca account
- Test connection: `snow connection test`
- Google Maps API key accessible
- Gemini API key accessible

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
│   └── dealers_sample.csv             # ~200 real crawled dealers
├── 00-setup/                          # Create WORKSHOP_DB, load data
├── 01-collect/                        # Explore DEALERS
├── 02-locate-google-maps/             # Google Maps EAI + UDF → DEALER_GOOGLE_MAP
├── 03-enrich-gemini/                  # Gemini EAI + UDF → DEALER_ADDRESS_STANDARD
├── 04-resolve/                        # Final resolution + comparison
├── optional-05-matching/              # Matching multi-niveaux → CONCESSION
├── optional-06-cortex-ai/             # Cortex AI vs Gemini comparison
├── optional-07-data-quality/          # DMFs on enriched data
├── optional-08-change-tracking/       # AGENCY_CHANGE_LOG
├── optional-09-scheduling/            # Snowflake Tasks for monthly runs
├── workshop_notebook.ipynb
├── prerequisites_email.md
└── methodology/
    └── workshop-template.md
```
