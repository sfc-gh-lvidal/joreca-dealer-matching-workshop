# Block 2 — Locate: Google Maps via External Access Integration

## Goal

Call the Google Maps API directly from Snowflake to find and enrich each dealer's location. This populates the `DEALER_GOOGLE_MAP` cache table.

## What the UDF does

For each dealer, the `FIND_GOOGLE_PLACE` UDF:
1. Calls **Find Place** (text search) with the dealer name + address → gets a `place_id`
2. Calls **Place Details** with that `place_id` → gets the full business info (normalized name, formatted address, GPS coordinates, phone, website)
3. Returns the results as a VARIANT (JSON)

The pipeline then:
- calls the API **once per dealer** and keeps the raw answers in `GMAP_RESULTS` (no repeated billing)
- writes the Place ID on the dealer row: `DEALERS.GOOGLE_PLACE_ID`
- fills the cache `DEALER_GOOGLE_MAP` with a `MERGE` (only new places), keyed by `GOOGLE_PLACE_ID`. Rolling table: a place is not fetched again next month.

Status returned by the UDF: `OK`, `NOT_FOUND` (no result), `ERROR` (bad key, quota, Places API disabled: read the `error` field).

## Architecture

```
DEALERS
    │
    └──► UDF FIND_GOOGLE_PLACE(agency_name, address, city, zip_code)
              │
              ├── Google Maps Find Place API
              └── Google Maps Place Details API
                       │
                       └──► DEALER_GOOGLE_MAP (GOOGLE_PLACE_ID → full details)
```

## The key point

This replaces the part of the pipeline where you extract data from MariaDB, build a request, call the Google Maps API from a Python script on Linux, and parse the response back into the database. Here it's one UDF call per row, executed inside Snowflake.

## Setup

1. Paste your key in `setup_eai_google.sql`, run it (requires ACCOUNTADMIN): network rule + secret + integration
2. Run `google_maps_udf.sql`: creates the UDF, tests it on 3 rows, then processes 10 dealers (`LIMIT 10`)
3. Check `gmap_status`: if all rows are `ERROR`, fix the key before going further

The API key is stored in a Snowflake SECRET: it never appears in SQL, in results or in error messages.
