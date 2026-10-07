# Block 3 — Enrich: the Gemini Batch API, driven from Snowflake

## Goal
Run **the same flow as production** (Gemini Batch API, your production prompt, Google Search grounding) without the Linux server. Results go to `DEALER_ADDRESS_STANDARD`.

## What replaces what
| Today (Linux + batch) | In Snowflake |
|-----------------------|--------------|
| Python builds a JSONL file from MariaDB | `SUBMIT_GEMINI_BATCH(n)` reads `DEALERS` and builds the JSONL in memory |
| Upload the file, create the batch job | Same procedure: Files API upload + `batchGenerateContent` |
| Cron / manual checks while waiting | `COLLECT_GEMINI_BATCH(NULL)`, or a **Task** every 5 minutes |
| Download the result file, parse, re-insert | Same procedure: download + `MERGE` into `DEALER_ADDRESS_STANDARD` |
| Prompt stored in code | Prompt stored as a file on the stage (`prompts/gemini_search_agency.txt`) |

## Objects
| Object | Role |
|--------|------|
| `GEMINI_BATCH_JOBS` | One row per job: `batches/…` name, state, counts, timestamps |
| `GEMINI_BATCH_REQUESTS` | JSONL `key` (`r0`, `r1`…) → `AGENCY_ID`, `SITE` |
| `SUBMIT_GEMINI_BATCH(n)` | Sends `n` dealers without a result and not already in a pending job (safe to re-run) |
| `COLLECT_GEMINI_BATCH(name)` | Checks the job; when `SUCCEEDED`, loads the results. `NULL` = every job not collected yet |
| `SEARCH_AGENCY(name, address)` | *Optional* interactive UDF, same prompt: debug one dealer, iterate on the prompt |

- Model: `gemini-2.5-flash` (constant `MODEL` in the procedures and the UDF).
- Batch price = **50% of the interactive price**. Target turnaround 24 h; a small job usually takes minutes.
- File mode (JSONL, up to 2 GB): the prompt is ~42 KB per request, so inline mode (20 MB max) would cap a job at ~450 dealers.

## Steps
1. Paste your key in `setup_eai_gemini.sql`, run it: `ALTER SECRET` (integration created by the admin). Skip it if the key is already set.
2. Run `gemini_batch.sql`: creates the tables and procedures, then `CALL SUBMIT_GEMINI_BATCH(10)`.
3. **Coffee break.** Then `CALL COLLECT_GEMINI_BATCH(NULL)` until `state = SUCCEEDED` and `collected > 0`.
4. Optional: `search_agency_udf.sql` — the interactive UDF, to test one dealer at a time.

## Errors
Every API error comes back as `{"status": "ERROR", "step": …, "error": …}` (bad key, quota, model…). Nothing is recorded in that case. Requests that fail inside a successful job land in `AI_JSON:error`.

## IS_REUSED
In production you reuse last month's result when the dealer did not change. The column is there; the workshop always calls the API (`IS_REUSED = FALSE`).

## Cost
`token_usage` gives the real average input / output tokens per dealer. Multiply by your monthly volume and the **batch** price to compare with your Google invoice and with Cortex AI (optional module 06).
