# [OPTIONAL] Cortex AI vs Gemini Comparison

## Goal

Run the same address standardization task through Snowflake's built-in Cortex AI instead of the Gemini external API, and compare results + costs.

## Why consider Cortex AI

- No EAI setup needed (no network rules, no secrets, no API keys)
- Data never leaves Snowflake
- Billed via Snowflake credits (no separate Google contract)
- One SQL function call: `SNOWFLAKE.CORTEX.AI_COMPLETE()`

## Same prompt, no web search
Cortex AI models do not browse the web: they can standardize what is in the input (name, address), but cannot find a SIRET or phone that is not given. Compare on the fields both can produce (standard address, cleaned name), and keep Gemini + Google Search for the research part, or feed Cortex with the Google Maps data from step 2.

## How to run

```sql
-- Same standardization task via Cortex AI
SELECT
    d.AGENCY_ID,
    d.AGENCY_NAME,
    SNOWFLAKE.CORTEX.AI_COMPLETE(
        'claude-3-5-haiku',
        CONCAT(
            'Standardize this French car dealer address. Return ONLY a JSON object with ',
            '{"standard_address":"...", "clean_agency_name":"...", "confidence":0.0-1.0}.\n\n',
            'Agency: ', d.AGENCY_NAME, '\n',
            'Address: ', d.ADDRESS, '\n',
            'City: ', d.CITY, '\n',
            'Zip: ', d.ZIP_CODE
        )
    ) AS CORTEX_RESULT
FROM DEALERS d
LIMIT 10;
```

## Cost comparison framework

| Component | Gemini (external) | Cortex AI (native) |
|-----------|------------------|-------------------|
| Setup | EAI + Network Rule + Secret | None |
| API key | Required (Google) | Not needed |
| Per-request cost | ~$0.01-0.05 (depends on model) | ~EUR 0.006 per 1K tokens (haiku) |
| Data residency | Leaves Snowflake to Google | Stays in Snowflake |
| Latency | Network round-trip | Internal |

Use the `token_usage` result of Block 3 (real tokens per dealer) and the current Cortex AI credit table to compute the monthly cost at your volume.
