# Block 2 — Locate: Google Maps via External Access Integration

## Goal

Call the Google Maps API directly from Snowflake to find and enrich each dealer's location. This populates the `DEALER_GOOGLE_MAP` cache table.

## What the UDF does

For each dealer, the `find_google_place` UDF:
1. Calls **Find Place** (text search) with the dealer name + address → gets a `place_id`
2. Calls **Place Details** with that `place_id` → gets the full business info (normalized name, formatted address, GPS coordinates, phone, website)
3. Returns the results as a VARIANT (JSON)

The results are cached in `DEALER_GOOGLE_MAP`, keyed by `GOOGLE_PLACE_ID`. This is a rolling table — once a place is looked up, it doesn't need to be looked up again next month.

## Architecture

```
DEALERS
    │
    └──► UDF find_google_place(agency_name, address, city, zip_code)
              │
              ├── Google Maps Find Place API
              └── Google Maps Place Details API
                       │
                       └──► DEALER_GOOGLE_MAP (GOOGLE_PLACE_ID → full details)
```

## The key point

This replaces the part of the pipeline where you extract data from MariaDB, build a request, call the Google Maps API from a Python script on Linux, and parse the response back into the database. Here it's one UDF call per row, executed inside Snowflake.

## Setup

1. Run `setup_eai_google.sql` (requires ACCOUNTADMIN) to create the network rule, secret, and integration
2. Run `google_maps_udf.sql` to create the UDF and populate `DEALER_GOOGLE_MAP`
