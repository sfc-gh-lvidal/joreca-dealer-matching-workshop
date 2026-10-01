# Block 1 — Collect: Explore the DEALERS data

## Goal

Explore the raw crawled dealer data. Understand the data quality issues. This is the equivalent of what their crawlers produce into MariaDB — now it's in Snowflake.

## Key observations to surface during the workshop

- Many SIRETs are missing (empty strings)
- Addresses are inconsistent (some have city embedded, some use department codes like "FR-74100")
- Agency names vary wildly for the same real dealership across different sites
- Some dealers appear on multiple sites with different AGENCY_IDs

## "But I need a Linux environment..."

Everything you see here — data in a table, queryable with SQL — was loaded from a CSV via Snow CLI. No MariaDB, no Linux server, no SSH. The data lives in Snowflake and you interact with it the same way you would from a terminal.
