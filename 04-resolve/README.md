# Block 4 — Resolve + Wrap-up

## Goal

Combine the outputs from Google Maps (step 2) and Gemini (step 3), resolve the final GOOGLE_PLACE_ID for each dealer, and compare with the production matching results.

## What "resolve" means

Each dealer may have:
- A GOOGLE_PLACE_ID from the Google Maps lookup (step 2)
- A standardized address from Gemini (step 3)
- A confirmation from Gemini on whether the Google Maps result matches

The resolve step writes the final GOOGLE_PLACE_ID into `DEALER_ADDRESS_STANDARD`. Workshop rule: keep the Place ID found in step 2 only if Gemini's `match_confidence_score` is >= 0.7 **and** the postal code found by Gemini appears in the Google Maps address. In production there is a second Gemini pass for ambiguous cases.

`DEALERS_ENRICHED` (view) puts side by side: raw crawl, Gemini result (name, standard address, SIRET), Google Maps result (address, GPS), confidence.

The end of `resolve_and_compare.sql` contains the cleanup commands (commented out).

## Next steps (post-workshop)

After resolve, the production pipeline continues with:
- **Step 5 (Consolidate):** Write enriched data back to DEALERS + CONCESSION
- **Step 6 (Match):** Link each dealer to a CONCESSION via JORECA_ID (multi-level matching)
- **Step 7 (Sync):** Update listing counts
- **Step 8 (Track):** Log changes via AGENCY_CHANGE_LOG

See the `optional-*` modules in this repo for guidance on implementing these.
