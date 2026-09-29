# Executive technical handover

Commit `3ce4c4c`. Labels follow the evidence vocabulary in `22_SOURCE_EVIDENCE_LEDGER.md`.

## The product

An invitation-gated member app. A prospective member enters an invitation code, signs in with
Apple, Google or an emailed one-time code, the server creates their member row from the invitation
(tier and, historically, admin rights come from the code), and a five-step onboarding records
archetype answers, feed interests and a consent version. After that the member lives in five tabs:
Pulse (home digest plus the full briefing at `/briefing`), Events, Aligned (gold and above), Me, and
Admin for administrators. A Corridor tab exists in code and is hidden from everyone.

## The architecture in one paragraph

The mobile client talks directly to Supabase with the public anon key and the member's JWT. Reads
and writes go through PostgREST, either to tables protected by RLS or to SECURITY DEFINER RPCs that
enforce their own checks. An access-token hook (`custom_access_token_hook`,
`supabase/migrations/20260301000004_auth_hook.sql:6`) stamps `tier` and `is_admin` into
`app_metadata`, which the client uses for navigation only. Six Deno Edge Functions run the news
pipeline, pushes and map refresh, called by pg_cron or by pg_net triggers carrying a shared secret
from Vault. Storage holds one private bucket, `uploads`. Push goes through the Expo push service.
Maps use Mapbox. News classification calls an OpenAI-compatible endpoint or Anthropic, selected by
environment variable. Diagrams are in `02`.

## Production state

iOS 1.2.5 build 37 is on the App Store. Android 1.2.5 version code 62 is on the closed Alpha track
and has never been on Play production. The database is PostgreSQL 17.6 with 23 members and four
administrator roles at 22 September. The backend has run unattended since July; the 5 September
report observed nine active cron jobs with no failures in 48 hours, but only four of those nine are
defined in version control. All of these are point-in-time statements that need re-reading.

## Most significant known risks

| ID | Risk | Status |
|---|---|---|
| HO-16 | No staging. Negative testing has nowhere safe to run. | OBSERVED |
| HO-04 | `redeem_invitation_code` has no throttle, so it is an unthrottled oracle for 30-bit six-character codes to anyone who can create an auth account. | POSSIBLY PRESENT, source-observed |
| HO-01 | `map_cache_projects`, `map_cache_states`, `map_cache_countries` have `USING (true)` for `authenticated`, bypassing the gold gate that containment added to the map functions. | POSSIBLY PRESENT, source-observed; table grants need live confirmation |
| HO-02, HO-03 | Approved projects readable by any authenticated account; project creators appear able to set their own project to `approved`. | POSSIBLY PRESENT |
| HO-05 | Invitation recipient-email binding compares a caller-supplied `p_email`, not the signed-in email. | STILL PRESENT in source |
| HO-07 | `is_admin()` ignores member status; a suspended administrator still passes admin checks. | POSSIBLY PRESENT |
| PR5-05 | No crash or error reporting in the shipped app. | STILL PRESENT |
| PR5-10 | Five of nine production cron schedules exist only in the database or a runbook. | STILL PRESENT in repository |
| HO-09 | Event and project cover uploads target a storage bucket named `public` that no migration creates and no policy covers. | LIKELY FAILURE; bucket existence EXTERNAL |
| PR5-04 | Android cannot reach production until 12 testers stay opted in for 14 days. | EXTERNAL |

Full register: `16_FINDINGS_REGISTER.csv`. Reconciliation with the 5 September report: `06`.

## Major unverified surfaces

Nothing below has a recorded device or runtime result at this commit: every sign-in method on
either platform, the iOS Google browser fallback, deep-link return on Android, token refresh after
long background, push delivery and tap routing from a killed app, event capacity under concurrency,
QR check-in, introductions end to end, account deletion follow-through, the throttle rejecting in
production, and any behaviour under a suspended account.

## Inherited decisions to respect

- Invitation-only membership. There is no open registration product path, even though the auth layer permits account creation (see `09`).
- Tier rules live in the database; the client only hides navigation. `TAB_VISIBILITY.aligned = 3` (`lib/theme.ts:194`) means gold and above, and containment mirrored that in `assert_aligned_map_access`. The user-facing copy says platinum; which is right is a product decision recorded in `21`.
- The news pipeline is deterministic: RSS and Google News in, one bounded classifier call per article, ranking in SQL, a hard monthly model budget. Do not turn it into an agent.
- Introductions are double opt-in with contact revealed only on approval. Direct mailto was deliberately retired.
- Pulse editions (hand-written, `pulse_editions`) and the algorithmic briefing (`news_articles`) are separate systems that share a tab.
- Android store builds must come from the GitHub Actions workflow that injects the upload keystore. Local EAS Android credentials are documented as the wrong key.
- The 22 September containment migration and the short-codes migration were amended after they ran so that they replay on an empty database. Production recorded them by version; the amended files will not re-run there. Their executed hashes are in `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`.

## What not to redesign during the sprint

The tab structure, the design system and its two token files, the ranking formula, the invitation
model, the onboarding flow's shape, the Aligned matching algorithm, the map, the admin console
layout, and the dependency set beyond what Sentry and Media V1 strictly need. Large issues go into
the findings register as Phase 2 with a written recommendation.

## What success looks like

- Every P0 and P1 authorisation finding reproduced or disproved with a real member JWT, fixed where confirmed, and covered by a negative pgTAP test that runs in CI.
- Invite, Apple, Google and email sign-in, refresh, relaunch, logout and re-login exercised on a physical iPhone and a physical Android device, with results in `11_DEVICE_TEST_MATRIX.csv`.
- An admin can publish an audio episode and a video; an authenticated member can play them on both platforms; a non-member cannot fetch the media bytes.
- Sentry, or an approved equivalent, receives a deliberate test error from a store or release-profile build.
- The nine cron schedules are in version control or their gap is documented exactly.
- `16_FINDINGS_REGISTER.csv` separates must fix before wider launch, should fix soon, and can follow later.
