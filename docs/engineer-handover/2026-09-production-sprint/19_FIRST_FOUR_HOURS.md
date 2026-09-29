# First four hours

No UI polish and no redesign in this window. The goal is a reproducible build, a verified picture of
the P0 findings, and a list of anything that blocks the sprint.

## Hour one: reproducible local build

- Clone, check out `release/v2-redesign-signed` at `3ce4c4c` or later, branch from it.
- `npm ci`, then `npm run lint`, `npm run typecheck`, `npm run verify:security`, `npm run test:ci`, and `deno test --allow-read --no-config supabase/functions`. Expected at `3ce4c4c`: 0 lint errors with 27 warnings, clean typecheck, verifier pass, 77 tests in 10 suites, 15 Deno tests.
- `supabase db start` and `supabase test db` with CLI 2.109.1. This proves the 58 migrations replay and the five pgTAP files pass.
- Start a development build on one device or simulator if a Mapbox download token is available; otherwise note it as a blocker.

## Hour two: environment and configuration

- Read `04` and settle with Jeremy where negative tests will run. Until that is settled, work only on local Supabase.
- Confirm in the Supabase dashboard (read-only): plan, backups, PITR, whether sign-up is enabled, access-token lifetime, the list of cron jobs (names and schedules only), Edge Function list and whether they verify JWTs, storage buckets and whether a `public` bucket exists.
- Confirm in EAS: environment variables for the production profile, especially the Google iOS client ID.

## Hour three: prior findings and P0 reproduction

- Read `06` P0 and P1 entries and `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`.
- On local Supabase, as real `authenticated` JWTs, reproduce or disprove:
  - HO-04: an auth user without a member row calling `redeem_invitation_code` repeatedly.
  - HO-01 and HO-02: a silver member and a non-member reading `map_cache_projects` and approved `projects`.
  - HO-25: first-time RSVP to an event with a capacity.
  - HO-07: a suspended administrator calling an admin RPC.
  - HO-03: a creator setting their own project to approved.
- Record each outcome in `16_FINDINGS_REGISTER.csv` with the exact SQL or request used.

## Hour four: authorisation matrix and blockers

- Start `07_AUTHORIZATION_MATRIX_STARTER.csv`: fill RESULT for the rows exercised above, add rows you find missing.
- Check which test identities and invitation codes exist on the agreed environment (`12`).
- Send Jeremy a short note: what reproduced, what did not, what access is still missing, and any decision needed (tier boundary for Aligned, closing sign-up at the Auth level, staging).
