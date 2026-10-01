# Block 3 — Enrich: Gemini search with your production prompt

## Goal
Call Gemini from Snowflake, with **your production prompt** and Google Search grounding, to find each dealer online and get a standardized address, SIRET, phone, website... Results go to `DEALER_ADDRESS_STANDARD`.

## What replaces what
| Today (Linux + batch) | In Snowflake |
|-----------------------|--------------|
| Export rows from MariaDB to a JSON file | Not needed: the UDF reads the table |
| Upload the file to the Gemini batch API, wait, download | One `SELECT SEARCH_AGENCY(...)` |
| Parse the result file and re-insert in the database | `INSERT ... SELECT` + JSON notation `AI_JSON:potential_matches[0]:standard_address` |
| Prompt stored in code | Prompt stored as a file on the stage (`prompts/gemini_search_agency.txt`) |

## The UDF `SEARCH_AGENCY(agency_name, address)`
- Reads the prompt file from the stage (`IMPORTS`) and sends it as the system instruction
- Sends the same inputs as your batch: `Agency Name: ...` / `Address: ...`
- Enables `google_search` so Gemini can do the online research the prompt asks for
- Returns the JSON defined by the prompt, plus `_usage` (input / output tokens)
- Model: `gemini-2.5-flash` (constant `MODEL` in the UDF: change it if you use another model in production)

To change the prompt: re-upload the file, then re-run the `CREATE FUNCTION`. No code change.

## Steps
1. Paste your key in `setup_eai_gemini.sql`, run it (requires ACCOUNTADMIN)
2. Run `search_agency_udf.sql`: creates the UDF, tests 3 rows, processes 10 dealers, shows tokens per call

Each call does web research: expect several seconds per dealer.

## IS_REUSED
In production you reuse last month's result when the dealer did not change. The column is there; the workshop always calls the API (`IS_REUSED = FALSE`).

## Cost
`token_usage` gives the real average input / output tokens per dealer. Multiply by your monthly volume to compare with your Google invoice and with Cortex AI (optional module 06).
