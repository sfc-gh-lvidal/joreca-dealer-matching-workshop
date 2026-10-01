# Block 4 — Resolve + Wrap-up

## Goal

Combine the outputs from Google Maps (step 2) and Gemini (step 3), resolve the final GOOGLE_PLACE_ID for each dealer, and compare with the production matching results.

## What "resolve" means

Each dealer may have:
- A GOOGLE_PLACE_ID from the Google Maps lookup (step 2)
- A standardized address from Gemini (step 3)
- A confirmation from Gemini on whether the Google Maps result matches

The resolve step picks the best GOOGLE_PLACE_ID and writes it into `DEALER_ADDRESS_STANDARD`. In production, there's a second Gemini pass here for ambiguous cases — we skip that in the workshop but the pattern is the same.

## Next steps (post-workshop)

After resolve, the production pipeline continues with:
- **Step 5 (Consolidate):** Write enriched data back to DEALERS + CONCESSION
- **Step 6 (Match):** Link each dealer to a CONCESSION via JORECA_ID (multi-level matching)
- **Step 7 (Sync):** Update listing counts
- **Step 8 (Track):** Log changes via AGENCY_CHANGE_LOG

See the `optional-*` modules in this repo for guidance on implementing these.
