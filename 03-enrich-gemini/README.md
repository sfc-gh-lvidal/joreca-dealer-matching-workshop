# Block 3 — Enrich: Gemini AI for Address Standardization

## Goal

Call the Gemini API from Snowflake to standardize addresses and verify dealer identity. This populates `DEALER_ADDRESS_STANDARD`, using `DEALER_GOOGLE_MAP` data as additional context.

## What the UDF does

For each dealer, the `standardize_address` UDF sends Gemini:
- The raw dealer info (name, address, city, zip)
- The Google Maps data we found in step 2 (if any)

Gemini returns:
- A standardized, clean address
- A verification of whether the Google Maps result matches the raw dealer
- A confidence assessment

## The IS_REUSED pattern

In production, Joreca reuses last month's results when the input hasn't changed. During the workshop we process everything fresh, but the `IS_REUSED` column in `DEALER_ADDRESS_STANDARD` is there to show the pattern. In production, you'd check if (AGENCY_ID, SITE) already has a result from the previous period and skip the API call.

## Setup

1. Run `setup_eai_gemini.sql` (requires ACCOUNTADMIN) — or reuse the same EAI if you added Gemini to the Google Maps one
2. Run `standardize_address_udf.sql` to create the UDF and populate `DEALER_ADDRESS_STANDARD`
