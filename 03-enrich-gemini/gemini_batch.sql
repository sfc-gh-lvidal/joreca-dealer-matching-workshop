-- ----------------------------------------------------------------------
-- Block 3 - Enrich with the Gemini BATCH API (what Joreca runs in production)
-- Same code as the matching cells of workshop_notebook.ipynb
-- ----------------------------------------------------------------------
-- Today:   Python on Linux builds a JSONL file -> upload -> batch job -> wait -> download -> re-import into MariaDB
-- Here:    the same Gemini Batch API, driven from Snowflake by two stored procedures:
--   SUBMIT_GEMINI_BATCH(n)    builds the JSONL from DEALERS, uploads it (Files API), creates the batch job
--   COLLECT_GEMINI_BATCH(job) checks the job; when SUCCEEDED, downloads the results into DEALER_ADDRESS_STANDARD
-- Batch API = 50% of the interactive price, asynchronous (target 24 h, usually minutes for a small job).
-- Same prompt (stage file), same Google Search grounding, same AI_JSON format as the interactive UDF.
USE ROLE WORKSHOP_DEV; USE DATABASE WORKSHOP_DB; USE SCHEMA PUBLIC; USE WAREHOUSE WORKSHOP_WH;

-- 1. Tracking tables: one row per batch job, and the JSONL key -> dealer mapping
CREATE TABLE IF NOT EXISTS GEMINI_BATCH_JOBS (
    BATCH_NAME      VARCHAR PRIMARY KEY,   -- batches/xxx, returned by Gemini
    DISPLAY_NAME    VARCHAR,
    MODEL           VARCHAR,
    INPUT_FILE      VARCHAR,               -- files/xxx: the uploaded JSONL
    N_REQUESTS      NUMBER,
    STATE           VARCHAR,               -- PENDING / RUNNING / SUCCEEDED / FAILED / CANCELLED / EXPIRED
    BATCH_STATS     VARIANT,               -- request / success / failure counts
    SUBMITTED_AT    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    LAST_CHECKED_AT TIMESTAMP_NTZ,
    COLLECTED_AT    TIMESTAMP_NTZ,         -- results loaded into DEALER_ADDRESS_STANDARD
    N_COLLECTED     NUMBER
);

CREATE TABLE IF NOT EXISTS GEMINI_BATCH_REQUESTS (
    BATCH_NAME  VARCHAR,
    REQUEST_KEY VARCHAR,                   -- "key" of the JSONL line (r0, r1, ...)
    AGENCY_ID   VARCHAR,
    SITE        VARCHAR
);

-- 2. Submit: build the JSONL (one GenerateContentRequest per dealer), upload it, create the batch job.
--    Only dealers without a result and not already in a pending job are sent: re-running is safe.
CREATE OR REPLACE PROCEDURE SUBMIT_GEMINI_BATCH(SAMPLE_SIZE NUMBER)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
IMPORTS = ('@WORKSHOP_DB.PUBLIC.WORKSHOP_STAGE/prompts/gemini_search_agency.txt')
HANDLER = 'submit'
EXTERNAL_ACCESS_INTEGRATIONS = (GEMINI_EAI)
SECRETS = ('gemini_key' = WORKSHOP_DB.PUBLIC.GEMINI_API_KEY)
AS
$$
import _snowflake
import json
import requests

BASE = "https://generativelanguage.googleapis.com"
import os
import sys

MODEL = "gemini-2.5-flash"

# Joreca's production prompt, versioned as a file on the stage (same file as the interactive UDF)
with open(os.path.join(sys._xoptions["snowflake_import_directory"], "gemini_search_agency.txt"), encoding="utf-8") as f:
    SYSTEM_PROMPT = f.read()


def _key():
    return _snowflake.get_generic_secret_string("gemini_key")


def _http_error(r):
    # Clean message only: never echo request headers (they contain the key)
    try:
        msg = r.json().get("error", {}).get("message", "")
    except Exception:
        msg = r.text[:300]
    return f"HTTP {r.status_code}: {msg}"


def _short_state(state):
    # The API returns BATCH_STATE_xxx (REST) or JOB_STATE_xxx (SDK docs): keep the last word
    return (state or "UNKNOWN").split("_")[-1]


def build_jsonl(rows):
    """One line per dealer: {"key": ..., "request": GenerateContentRequest}. Same request as the interactive UDF."""
    lines = []
    for i, row in enumerate(rows):
        lines.append(json.dumps({
            "key": f"r{i}",
            "request": {
                "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
                "contents": [{"role": "user", "parts": [{"text": f"Agency Name: {row['AGENCY_NAME']}\nAddress: {row['ADDR']}"}]}],
                "tools": [{"google_search": {}}],
                "generation_config": {"temperature": 0.1},
            },
        }, ensure_ascii=False))
    return "\n".join(lines) + "\n"


def submit(session, sample_size):
    key = _key()
    # Dealers without a Gemini result yet, and not already waiting in a pending batch
    rows = session.sql(f"""
        SELECT d.AGENCY_ID, d.SITE, d.AGENCY_NAME,
               CONCAT_WS(', ', d.ADDRESS, d.ZIP_CODE, d.CITY, 'France') AS ADDR
        FROM DEALERS d
        WHERE NOT EXISTS (SELECT 1 FROM DEALER_ADDRESS_STANDARD s
                          WHERE s.AGENCY_ID = d.AGENCY_ID AND s.SITE = d.SITE)
          AND NOT EXISTS (SELECT 1 FROM GEMINI_BATCH_REQUESTS r
                          JOIN GEMINI_BATCH_JOBS j ON j.BATCH_NAME = r.BATCH_NAME
                          WHERE r.AGENCY_ID = d.AGENCY_ID AND r.SITE = d.SITE
                            AND j.COLLECTED_AT IS NULL
                            AND j.STATE NOT IN ('FAILED', 'CANCELLED', 'EXPIRED'))
        ORDER BY d.AGENCY_ID
        LIMIT {int(sample_size)}""").collect()
    if not rows:
        return {"status": "NOTHING_TO_DO", "message": "every dealer already has a result or is in a pending batch"}

    data = build_jsonl([r.as_dict() for r in rows]).encode("utf-8")
    display_name = f"joreca-dealers-{len(rows)}"

    # 1. Upload the JSONL file (Files API, resumable protocol: start, then upload + finalize)
    start = requests.post(f"{BASE}/upload/v1beta/files",
                          headers={"x-goog-api-key": key,
                                   "X-Goog-Upload-Protocol": "resumable",
                                   "X-Goog-Upload-Command": "start",
                                   "X-Goog-Upload-Header-Content-Length": str(len(data)),
                                   "X-Goog-Upload-Header-Content-Type": "application/jsonl",
                                   "Content-Type": "application/json"},
                          json={"file": {"display_name": display_name}}, timeout=60)
    upload_url = start.headers.get("x-goog-upload-url")
    if start.status_code != 200 or not upload_url:
        return {"status": "ERROR", "step": "upload start", "error": _http_error(start)}
    up = requests.post(upload_url,
                       headers={"x-goog-api-key": key,
                                "Content-Length": str(len(data)),
                                "X-Goog-Upload-Offset": "0",
                                "X-Goog-Upload-Command": "upload, finalize"},
                       data=data, timeout=300)
    if up.status_code != 200:
        return {"status": "ERROR", "step": "upload", "error": _http_error(up)}
    input_file = up.json()["file"]["name"]

    # 2. Create the batch job on that file
    job = requests.post(f"{BASE}/v1beta/models/{MODEL}:batchGenerateContent",
                        headers={"x-goog-api-key": key},
                        json={"batch": {"display_name": display_name,
                                        "input_config": {"file_name": input_file}}},
                        timeout=60)
    if job.status_code != 200:
        return {"status": "ERROR", "step": "create batch", "error": _http_error(job)}
    op = job.json()
    batch_name = op["name"]
    state = _short_state(op.get("metadata", {}).get("state", "PENDING"))

    # 3. Track the job and the key -> dealer mapping in Snowflake
    session.sql("""INSERT INTO GEMINI_BATCH_JOBS (BATCH_NAME, DISPLAY_NAME, MODEL, INPUT_FILE, N_REQUESTS, STATE)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                params=[batch_name, display_name, MODEL, input_file, len(rows), state]).collect()
    mapping = [[batch_name, f"r{i}", r["AGENCY_ID"], r["SITE"]] for i, r in enumerate(rows)]
    session.create_dataframe(mapping, schema=["BATCH_NAME", "REQUEST_KEY", "AGENCY_ID", "SITE"]) \
           .write.mode("append").save_as_table("GEMINI_BATCH_REQUESTS", column_order="name")

    return {"status": "SUBMITTED", "batch_name": batch_name, "requests": len(rows),
            "input_file": input_file, "state": state}
$$;

-- 3. Collect: check the job state; when SUCCEEDED, download the result file and MERGE into DEALER_ADDRESS_STANDARD.
--    COLLECT_GEMINI_BATCH(NULL) processes every job not collected yet (that is what the Task calls).
CREATE OR REPLACE PROCEDURE COLLECT_GEMINI_BATCH(BATCH_NAME VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'collect'
EXTERNAL_ACCESS_INTEGRATIONS = (GEMINI_EAI)
SECRETS = ('gemini_key' = WORKSHOP_DB.PUBLIC.GEMINI_API_KEY)
AS
$$
import _snowflake
import json
import requests

BASE = "https://generativelanguage.googleapis.com"
import re


def _key():
    return _snowflake.get_generic_secret_string("gemini_key")


def _http_error(r):
    # Clean message only: never echo request headers (they contain the key)
    try:
        msg = r.json().get("error", {}).get("message", "")
    except Exception:
        msg = r.text[:300]
    return f"HTTP {r.status_code}: {msg}"


def _short_state(state):
    # The API returns BATCH_STATE_xxx (REST) or JOB_STATE_xxx (SDK docs): keep the last word
    return (state or "UNKNOWN").split("_")[-1]


def _parse_json_text(text):
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text.strip())
    start, end = text.find("{"), text.rfind("}")
    return json.loads(text[start:end + 1])


def parse_result_line(line):
    """One line of the result file -> (key, result dict). Same result shape as the interactive UDF."""
    obj = json.loads(line)
    key = obj.get("key")
    resp = obj.get("response")
    if resp is None and "candidates" in obj:      # line without wrapper
        resp = obj
    if not resp:
        return key, {"error": json.dumps(obj.get("error") or obj.get("status") or obj)[:500]}
    try:
        text = "".join(p.get("text", "") for p in resp["candidates"][0]["content"]["parts"])
        out = _parse_json_text(text)
    except Exception as e:
        out = {"error": f"{type(e).__name__}: could not parse the model answer"}
    out["_usage"] = resp.get("usageMetadata")
    return key, out


def _collect_one(session, key, batch_name):
    r = requests.get(f"{BASE}/v1beta/{batch_name}", headers={"x-goog-api-key": key}, timeout=60)
    if r.status_code != 200:
        return {"batch_name": batch_name, "status": "ERROR", "error": _http_error(r)}
    op = r.json()
    meta = op.get("metadata", {})
    state = _short_state(meta.get("state"))
    stats = meta.get("batchStats", {})
    session.sql("""UPDATE GEMINI_BATCH_JOBS
                   SET STATE = ?, BATCH_STATS = PARSE_JSON(?), LAST_CHECKED_AT = CURRENT_TIMESTAMP()
                   WHERE BATCH_NAME = ?""",
                params=[state, json.dumps(stats), batch_name]).collect()
    if state != "SUCCEEDED":
        out = {"batch_name": batch_name, "state": state, "stats": stats}
        if op.get("error"):
            out["error"] = op["error"].get("message")
        return out

    # The result file name is in response.responsesFile (REST) or metadata.output.responsesFile
    resp = op.get("response", {})
    result_file = (resp.get("responsesFile")
                   or resp.get("output", {}).get("responsesFile")
                   or meta.get("output", {}).get("responsesFile"))
    if not result_file:
        return {"batch_name": batch_name, "state": state, "status": "ERROR", "error": "no responsesFile in the batch output"}
    dl = requests.get(f"{BASE}/download/v1beta/{result_file}:download",
                      params={"alt": "media"}, headers={"x-goog-api-key": key}, timeout=300)
    if dl.status_code != 200:
        return {"batch_name": batch_name, "state": state, "status": "ERROR", "error": _http_error(dl)}

    keys = {row["REQUEST_KEY"]: (row["AGENCY_ID"], row["SITE"]) for row in session.sql(
        "SELECT REQUEST_KEY, AGENCY_ID, SITE FROM GEMINI_BATCH_REQUESTS WHERE BATCH_NAME = ?",
        params=[batch_name]).collect()}
    results = []
    for line in dl.text.splitlines():
        if not line.strip():
            continue
        k, out = parse_result_line(line)
        if k in keys:
            results.append([keys[k][0], keys[k][1], json.dumps(out, ensure_ascii=False)])

    if results:
        session.create_dataframe(results, schema=["AGENCY_ID", "SITE", "AI_TEXT"]) \
               .write.mode("overwrite").save_as_table("GEMINI_BATCH_LOADED", table_type="temporary")
        # Same target and same columns as the interactive flow: AI_JSON + AI_STANDARD_ADDRESS
        session.sql("""
            MERGE INTO DEALER_ADDRESS_STANDARD t
            USING (SELECT AGENCY_ID, SITE, PARSE_JSON(AI_TEXT) AS AI FROM GEMINI_BATCH_LOADED) s
            ON t.AGENCY_ID = s.AGENCY_ID AND t.SITE = s.SITE
            WHEN MATCHED THEN UPDATE SET
                AI_JSON = s.AI,
                AI_STANDARD_ADDRESS = s.AI:potential_matches[0]:standard_address::VARCHAR,
                IS_REUSED = FALSE
            WHEN NOT MATCHED THEN INSERT (AGENCY_ID, SITE, AI_JSON, AI_STANDARD_ADDRESS, IS_REUSED)
                VALUES (s.AGENCY_ID, s.SITE, s.AI, s.AI:potential_matches[0]:standard_address::VARCHAR, FALSE)
        """).collect()
    session.sql("""UPDATE GEMINI_BATCH_JOBS SET COLLECTED_AT = CURRENT_TIMESTAMP(), N_COLLECTED = ?
                   WHERE BATCH_NAME = ?""", params=[len(results), batch_name]).collect()
    return {"batch_name": batch_name, "state": state, "stats": stats, "collected": len(results)}


def collect(session, batch_name):
    key = _key()
    if batch_name:
        names = [batch_name]
    else:  # all jobs not collected yet and not in a final error state (used by the Task)
        names = [r["BATCH_NAME"] for r in session.sql("""
            SELECT BATCH_NAME FROM GEMINI_BATCH_JOBS
            WHERE COLLECTED_AT IS NULL AND STATE NOT IN ('FAILED', 'CANCELLED', 'EXPIRED')""").collect()]
    try:
        return [_collect_one(session, key, n) for n in names]
    except Exception as e:
        return [{"status": "ERROR", "error": f"{type(e).__name__}: {str(e)[:300]}"}]
$$;

-- 4. Run it
CALL SUBMIT_GEMINI_BATCH(10  /* SAMPLE_SIZE: number of dealers sent to Gemini */);

SELECT BATCH_NAME, STATE, N_REQUESTS, BATCH_STATS, SUBMITTED_AT, LAST_CHECKED_AT, COLLECTED_AT
FROM GEMINI_BATCH_JOBS ORDER BY SUBMITTED_AT DESC;

-- Coffee break: re-run until state = SUCCEEDED and "collected" > 0 (a 10-dealer job usually takes minutes)
CALL COLLECT_GEMINI_BATCH(NULL);

-- 5. Optional: let Snowflake poll for you every 5 minutes (needs EXECUTE TASK, see admin_prereqs.sql)
-- CREATE OR REPLACE TASK COLLECT_GEMINI_BATCH_TASK
--     WAREHOUSE = WORKSHOP_WH
--     SCHEDULE = '5 MINUTE'
-- AS CALL COLLECT_GEMINI_BATCH(NULL);
-- ALTER TASK COLLECT_GEMINI_BATCH_TASK RESUME;
-- ALTER TASK COLLECT_GEMINI_BATCH_TASK SUSPEND;   -- after the workshop
