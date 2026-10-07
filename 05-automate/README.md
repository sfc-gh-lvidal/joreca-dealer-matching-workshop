# Block 5 — Automate it

Each step becomes a **stored procedure**, and a **task graph** chains them on a schedule: no Linux server, no cron.

```
PIPELINE_MONTHLY (cron: 1st of the month)   CALL RUN_LOCATE(n)              -- step 2, new dealers only
   └─▶ PIPELINE_ENRICH (AFTER the root)     CALL SUBMIT_GEMINI_BATCH(n)     -- step 3a, sends the batch job
PIPELINE_COLLECT (every 5 minutes)          CALL RUN_COLLECT_AND_RESOLVE()  -- step 3b + step 4 when the job is done
```

Two chains because the Gemini batch is asynchronous: chain 1 starts the job, chain 2 waits for it.

| Procedure | Wraps | Incremental rule |
|-----------|-------|------------------|
| `RUN_LOCATE(n)` | Block 2 | Calls Google only for dealers never located successfully |
| `SUBMIT_GEMINI_BATCH(n)` | Block 3 | Dealers without a result and not in a pending job |
| `RUN_COLLECT_AND_RESOLVE()` | Block 3b + 4 | Loads finished jobs, resolves rows not resolved yet |

## Steps
1. Run blocks 2 and 3 first (they create `FIND_GOOGLE_PLACE`, `SUBMIT_GEMINI_BATCH`, `COLLECT_GEMINI_BATCH`).
2. `snow sql -f 05-automate/automate_pipeline.sql`: procedures, tasks, `EXECUTE TASK PIPELINE_MONTHLY`, history.
3. After the batch is done: `EXECUTE TASK PIPELINE_COLLECT;`
4. Snowsight › Transformation › Tasks shows the graph and every run.

## Notes
- Needs the global `EXECUTE TASK` privilege for `WORKSHOP_DEV` (in `00-setup/admin_prereqs.sql`).
- `EXECUTE TASK` runs a suspended root but skips suspended children: `PIPELINE_ENRICH` is resumed, the root stays suspended until production.
- Production: `ALTER TASK PIPELINE_MONTHLY RESUME; ALTER TASK PIPELINE_COLLECT RESUME;`
- **After the workshop: suspend the 3 tasks** (last statement of the script).
