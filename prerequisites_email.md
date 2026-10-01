# Prerequisites Email — Workshop "Dealer Matching on Snowflake"

**Send ~1 week before the workshop (around Oct 1st)**

---

**Subject:** Workshop Oct 8 — Dealer Matching on Snowflake — Prerequisites

Hi Théane, [other devs],

Looking forward to the hands-on workshop next Wednesday (Oct 8, 15h00–17h30) at Snowflake's offices, rue de Châteaudun.

To make the most of our time together, here are a few things to prepare beforehand:

## To install

- **Snow CLI** — Snowflake's command-line interface:
  ```bash
  pip install snowflake-cli-labs
  ```
  Or on macOS: `brew install snowflake-cli`

- **Python 3.8+** — you probably already have this

- **VS Code** (recommended) — with the Snowflake extension

- **Git** — to clone the workshop repository

## To prepare

- **Snowflake access:** make sure you have a user on the Joreca Snowflake account and can log in.

- **Test your connection:**
  ```bash
  snow connection add
  snow connection test
  ```

- **API keys:** please have your **Google Maps API key** (with the Places API enabled on the Google Cloud project) and your **Gemini API key**. We'll use them to call these APIs directly from Snowflake, with the same search prompt you use today.

- **Permissions:** creating the API integrations requires the ACCOUNTADMIN role (or the CREATE INTEGRATION privilege). If none of the participants has it, please tell us beforehand.

## What we'll build

We'll work on a sample of your real crawled dealer data (~200 records) and build the core enrichment pipeline inside Snowflake:

1. **Load and explore** the DEALERS data (step 1 of your pipeline)
2. **Call Google Maps** from Snowflake to find and enrich dealer locations (step 2)
3. **Call Gemini** from Snowflake with your production search prompt (step 3), and measure the tokens per dealer
4. **Resolve** the final enriched output (step 4)

By the end, you'll have your pipeline steps 1–4 running in Snowflake with no external server needed.

## Optional reading

- [Snowpark Python](https://docs.snowflake.com/en/developer-guide/snowpark/python/index)
- [Snow CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index)
- [External Access Integrations](https://docs.snowflake.com/en/developer-guide/external-network-access/external-network-access-overview)

See you Wednesday!

Louis
