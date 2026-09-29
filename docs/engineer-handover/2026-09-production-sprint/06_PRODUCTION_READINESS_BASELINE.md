# Production-readiness baseline

Commit `3ce4c4c`, 29 September 2026. This file reconciles every earlier readiness finding against
current code and then states one current baseline. It does not replace the earlier reports; they are
preserved where they are.

## Earlier reports found

| Report | Where | Finding IDs | Scope |
|---|---|---|---|
| "AMARI App Production Readiness", 5 September 2026, 21 pages | Owner's Downloads folder as a PDF; not in the repository. Built from release HEAD `6face8d` and live production SQL | None. The report uses headings and severity words only | Whole product, production data, stores |
| External reviewer threat model and authorisation matrix, 21 September 2026 | `docs/EXTERNAL_REVIEWER_THREAT_MODEL.md`, `docs/EXTERNAL_REVIEWER_AUTHORISATION_MATRIX.md` | Section-based | Invitation and reviewer access |
| P0 containment record, 22 September 2026 | `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`, `docs/evidence/` | Controls table | The stranger-to-admin chain |
| Security hardening roadmap | `docs/SECURITY-HARDENING-ROADMAP.md` | None | Older; line 25 still claims invite rate limiting as a foundation that was removed and later re-added differently |

Because the 5 September report carries no identifiers, this pack assigns `PR5-01` onward in the
order the report raises each finding, so later work can refer to them stably. New findings from
this inspection use `HO-` identifiers.

## Reconciliation of the 5 September report

Status vocabulary: STILL PRESENT, POSSIBLY PRESENT, APPARENTLY CHANGED (REVERIFY), FIXED WITH
EVIDENCE, CANNOT VERIFY, EXTERNAL VERIFICATION REQUIRED. "Fixed with evidence" here means the
source and a captured production catalogue agree; it still needs one live re-run by Algene.

| ID | 5 Sep finding, as the report states it | 5 Sep severity | Status at `3ce4c4c` | Evidence now |
|---|---|---|---|---|
| PR5-01 | Map functions return member project data to unauthenticated callers | Critical | FIXED WITH EVIDENCE for the functions; residual HO-01 on the cache tables | `20260921000001:378-520`; 22 Sep catalogue anon=false |
| PR5-02 | Invite redemption trusts caller-supplied user id; PUBLIC and anon execute | Critical | FIXED WITH EVIDENCE; residuals HO-04, HO-05 | `20260921000001:222-228`; 22 Sep catalogue |
| PR5-03 | Invite validation is an unthrottled oracle over 1,216 valid codes | Critical | APPARENTLY CHANGED (REVERIFY). Codes expired and reissued; throttle added; rejection not proven at runtime | `DEPLOYMENT_RECORD.md`; `20260922000002:103-165` |
| PR5-04 | Android has no public distribution | Critical | EXTERNAL VERIFICATION REQUIRED. 6 of 12 testers opted in on 22 Sep per owner notes | Play Console |
| PR5-05 | No crash reporting, analytics or error aggregation | Critical | STILL PRESENT | `package.json`; `lib/sentry.ts` |
| PR5-06 | Feed query has no scaling story | High | STILL PRESENT. `get_news_feed` last redefined 18 Jul | `20260718000001:151` |
| PR5-07 | Push fan-out will not survive a large audience | High | STILL PRESENT | `send-briefing-push/index.ts:112-121` |
| PR5-08 | Consent basis missing for 21 of 23 members | High | CANNOT VERIFY without a production count. New onboarding writes `consent_version` | `app/(onboarding)/index.tsx:35` |
| PR5-09 | Account deletion is a request flag | High | STILL PRESENT | `20260425000001:5` |
| PR5-10 | Half the cron schedule is outside version control | High | STILL PRESENT. Four jobs in migrations | `20260301000005_cron_jobs.sql` |
| PR5-11 | Legacy API keys active alongside new keys | High | EXTERNAL VERIFICATION REQUIRED | Supabase dashboard |
| PR5-12 | Repository is public | High | FIXED WITH EVIDENCE. Private on 29 Sep via `gh repo view` | Exposed history remains exposed |
| PR5-13 | No user interface covered by a rendering test | Medium | STILL PRESENT. 77 tests, node environment | `jest.config.js`; local run 29 Sep |
| PR5-14 | Stale tier map in `TierGate` | Medium | STILL PRESENT, unimported | `components/TierGate.tsx:6` |
| PR5-15 | Two competing design-token systems | Medium | STILL PRESENT | `lib/constants.ts`, `lib/theme.ts` |
| PR5-16 | Dead surfaces shipping to members | Medium | STILL PRESENT | `lib/theme.ts:195`; stubs; orphaned `IntelligenceFeed.tsx` |
| PR5-17 | Silver members see a smaller app | Medium | STILL PRESENT as a product choice; copy says Platinum, rule is gold | `lib/theme.ts:194`; `app/(tabs)/aligned/_layout.tsx:26` |
| PR5-18 | iOS Google Sign-In runs the browser fallback | Medium | EXTERNAL VERIFICATION REQUIRED (EAS environment) | `lib/googleAuth.ts:30-33` |
| PR5-19 | Data hygiene in the news pipeline | Medium | CANNOT VERIFY without production reads | 5 Sep report |
| PR5-20 | Client resilience untested (cache, SecureStore size) | Medium | STILL PRESENT in source; REQUIRES DEVICE TEST | `lib/queryClient.ts:6-7` |
| PR5-21 | Store listing presents as an individual; 17+ rating | Medium | EXTERNAL VERIFICATION REQUIRED | Consoles |
| PR5-22 | Documentation has drifted again | Medium | STILL PRESENT; see HO-21 | `README.md:12` and others |
| PR5-23 | Supabase plan and backup posture unconfirmed | Medium | EXTERNAL VERIFICATION REQUIRED | Dashboard |
| PR5-24 | npm audit: 44 advisories, none bundled | Informational | CANNOT VERIFY bundle reach. Production-dependency audit now reports 34 (2 critical, 10 high); see HO-20 | Local audit 29 Sep |

The 5 September "What is built" table also listed media uploads as partial and podcasts and video
as schema only. That remains accurate (HO-09, HO-11).

## Reconciliation of the 21 and 22 September findings

| Finding | Status at `3ce4c4c` | Evidence |
|---|---|---|
| Predictable bootstrap invitation pool, 12 admin-capable codes | FIXED WITH EVIDENCE. 0 valid unused admin-capable, 0 bootstrap after 22 Sep | `docs/evidence/after-20260922T011536Z-statement-one.csv` |
| `check_rate_limit` and `cleanup_rate_limits` callable by anon | FIXED WITH EVIDENCE | Same file, section 3 |
| New functions default to PUBLIC execute | APPARENTLY CHANGED (REVERIFY). `alter default privileges ... revoke execute on functions from public` at `20260921000001:709` applies to functions created after it; existing functions keep their ACLs. 10 SECURITY DEFINER functions retained PUBLIC execute at 22 Sep | Same file, section 2 summary |
| Apple private-relay exemption in recipient binding | STILL PRESENT, and wider than recorded: see HO-05 | `20260921000001:255-262` |
| Burned production code and a named person's email in `scripts/verify-mobile-flows.mjs` and `docs/*-ANDROID-TEST-SCRIPT.md` (a tester script whose file name carries a first name) | STILL PRESENT in the repository (4 and 2 code-shaped strings). The code was already redeemed at 21 Sep | Files; `live-verification-targeted-codes-20260921.csv` |
| `supabase/seed.sql` literal codes | STILL PRESENT in the repository; not present in production at 21 Sep | Same evidence file |
| Keystore workflow with an unmasked password input | STILL PRESENT; see HO-18. Play App Signing status EXTERNAL | `.github/workflows/setup-keystore.yml` |
| Security verifier does not scan migrations | STILL PRESENT; see HO-22 | `scripts/verify-security.mjs:5` |
| Production had one migration more than the repository (`repair_degraded_feeds`) | FIXED in repository: `20260720000001_repair_degraded_feeds.sql` is present. Whether production now has more than the repository's 58 is EXTERNAL | `supabase/migrations/` |

## Numbers that moved

| Measure | Earlier figure | Current observed | Source of current figure |
|---|---|---|---|
| Tables | ~46 (brief), 46 (5 Sep), 47 app tables (21 Sep live) | 48 application tables defined in migrations, all with RLS enabled | Parser over 58 migrations at `3ce4c4c` |
| SECURITY DEFINER functions | ~60 (brief), 67 live on 21 Sep, 70 in the 21 Sep static parse | 65 application functions in source, matching the 22 Sep live catalogue's 68 minus 3 PostGIS `st_estimatedextent` overloads | Parser; `after-...statement-one.csv` |
| Migrations | 56 (5 Sep) | 58 | `supabase/migrations/` |
| Valid unused invitations | 1,216 (5 Sep) | 9 at 22 Sep, before the short-codes migration expired one more and before any later issuance | `DEPLOYMENT_RECORD.md` |

## Current baseline

Ordered by severity. The same rows, with reproduction and ownership columns, are in
`16_FINDINGS_REGISTER.csv`. "Requires production test" means a read-only check agreed with the
owner unless stated otherwise.

### P0, must fix or disprove before wider launch

#### HO-01: map_cache_projects, map_cache_states, map_cache_countries

| Field | Value |
|---|---|
| Severity | P0 |
| Surface | map_cache_projects, map_cache_states, map_cache_countries |
| Description | The three map cache tables have SELECT policies USING (true) for authenticated, so any signed-in account, including one with no member row, can read project names, descriptions, creator first names, image URLs, external links and coordinates, bypassing the gold gate added to the map functions on 22 Sep. |
| Why it matters | The containment migration and docs/EXTERNAL_TESTER_ACCESS_RUNBOOK.md state that member-tier testers cannot reach project data; this path contradicts that. |
| Evidence | supabase/migrations/20260326000001_map_feature.sql:128-156<br>client reads the table directly at app/(tabs)/aligned/index.tsx:393-396 and app/(tabs)/profile.tsx:247 |
| Reproduction approach | With a JWT for a silver member and for an auth user with no member row: GET /rest/v1/map_cache_projects?select=*. Control: anon GET must return 401 or empty. |
| Current status | POSSIBLY PRESENT |
| Recommended next step | Confirm live policy and grants read-only. Fix by gating the policy on is_active_member() and tier, and update the two client reads in the same PR. |
| Owner | Algene |
| Requires production test? | YES, read-only |
| Requires user decision? | YES, tier boundary gold or platinum |

#### HO-04: redeem_invitation_code

| Field | Value |
|---|---|
| Severity | P0 |
| Surface | redeem_invitation_code |
| Description | Redemption has no throttle, so it is a second, unthrottled oracle for the six-character invitation codes introduced on 22 Sep. |
| Why it matters | Short codes are 30 bits (20260922000002:6-14). The migration states they are only safe because validation is throttled. Any person who can create an auth account can call redeem repeatedly; a wrong guess returns invalid_or_expired and writes nothing. |
| Evidence | supabase/migrations/20260921000001_p0_invitation_containment.sql:199-340<br>20260922000002_short_codes_and_validation_throttle.sql:6-14 |
| Reproduction approach | On local Supabase: create an auth user without a member row, call redeem_invitation_code in a loop with random six-character codes, count refusals versus rate_limited. |
| Current status | POSSIBLY PRESENT |
| Recommended next step | Reproduce locally, then add a per-auth-user attempt limit inside redeem and a pgTAP test that the Nth attempt is refused. Confirm live body matches source. |
| Owner | Algene |
| Requires production test? | YES, read-only body comparison |
| Requires user decision? | NO |
| Notes | Depends on sign-up being open in production (EXTERNAL); the client requests shouldCreateUser true and Apple and Google create users on first sign-in. |

#### HO-16: All EAS profiles and Supabase

| Field | Value |
|---|---|
| Severity | P0 |
| Surface | All EAS profiles and Supabase |
| Description | No staging or test environment exists; every build profile targets the production Supabase project. |
| Why it matters | Negative authorisation tests, migration rehearsal and device QA have nowhere safe to run, so the sprint either tests on production or does not test. |
| Evidence | eas.json:13,31,50<br>docs/EXTERNAL_REVIEWER_ACCESS_PLAN.md |
| Reproduction approach | Read eas.json profiles; confirm in the Supabase dashboard that only one project exists. |
| Current status | STILL PRESENT |
| Recommended next step | Owner chooses local-only, staging project, or branching (04). Algene then adds an EAS profile if staging is chosen. |
| Owner | Jeremy |
| Requires production test? | NO |
| Requires user decision? | YES |
| Notes | Blocks safe execution of the sprint, not the app. |

#### HO-25: rsvp_to_event

| Field | Value |
|---|---|
| Severity | P0 |
| Surface | rsvp_to_event |
| Description | For events with a capacity, a first-time RSVP appears to write no row while returning success. |
| Why it matters | Members would hold a success message and no ticket; capacity counts would be wrong; the defect is silent. |
| Evidence | supabase/migrations/20260710000002_gold_tier_functions.sql:24-49 |
| Reproduction approach | Local Supabase: create an event with capacity 10, RSVP as a member who has never RSVPd, then select from event_rsvps. |
| Current status | LIKELY FAILURE |
| Recommended next step | Reproduce first. Fix by testing v_existing.id rather than FOUND, add a pgTAP test for first-time RSVP with and without capacity. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-05: Mobile app

| Field | Value |
|---|---|
| Severity | P0 |
| Surface | Mobile app |
| Description | No crash or error reporting is installed; lib/sentry.ts and lib/posthog.ts are guarded no-op shims and lib/reportError.ts writes to console.error. |
| Why it matters | Crashes and failed RPCs in production are invisible, and without OTA any fix needs a store round trip. |
| Evidence | package.json (no @sentry/react-native)<br>lib/sentry.ts:1-30<br>lib/reportError.ts |
| Reproduction approach | Search package.json and lib/ for an installed SDK. |
| Current status | STILL PRESENT |
| Recommended next step | Install @sentry/react-native with its Expo plugin, use an EXPO_PUBLIC_ DSN name, upload source maps from EAS, prove a deliberate error from a release-profile build. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | YES, account and cost |
| Notes | Brief classes this P1; kept P0 here because every other sprint result depends on seeing failures. |

### P1, fix in this sprint where achievable

#### HO-02: projects SELECT policy

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | projects SELECT policy |
| Description | Approved projects are readable by any authenticated account; the policy has no is_active_member() or tier condition. |
| Why it matters | Same exposure class as HO-01 through the base table. |
| Evidence | supabase/migrations/20260326000001_map_feature.sql:78-80 |
| Reproduction approach | As a no-member-row auth user: GET /rest/v1/projects?status=eq.approved. |
| Current status | POSSIBLY PRESENT |
| Recommended next step | Confirm live; align with the HO-01 decision. |
| Owner | Algene |
| Requires production test? | YES, read-only |
| Requires user decision? | YES |

#### HO-03: projects creator policy

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | projects creator policy |
| Description | The creator policy is FOR ALL with USING (auth.uid() = creator_id) and no WITH CHECK or status guard, so a creator appears able to update their own project status to approved without admin review. |
| Why it matters | Bypasses moderation; the map cache then publishes it. |
| Evidence | supabase/migrations/20260326000001_map_feature.sql:73-76<br>no status trigger among the three projects triggers |
| Reproduction approach | Local: as a member, insert a pending project, then PATCH status=approved on it. |
| Current status | POSSIBLY PRESENT |
| Recommended next step | Reproduce; split the policy into insert and update with a check that status stays pending for non-admins, or add a trigger. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-05: redeem_invitation_code recipient binding

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | redeem_invitation_code recipient binding |
| Description | The recipient-email check compares the caller-supplied p_email, not the signed-in account email, and exempts any address ending privaterelay.appleid.com. |
| Why it matters | A person holding an invitation addressed to someone else can redeem it by passing the addressee email or any relay-shaped string; the binding is not a control. |
| Evidence | supabase/migrations/20260921000001_p0_invitation_containment.sql:255-262<br>client passes state.user.email at providers/AuthProvider.tsx:203 |
| Reproduction approach | Local: create a recipient-bound invitation, sign in as a different email user, call redeem with p_email set to the recipient address. |
| Current status | STILL PRESENT |
| Recommended next step | Read the email from auth.users for auth.uid() inside the function; decide the Apple relay policy with the owner. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | YES, Apple relay policy |
| Notes | Memory of 21 Sep recorded the relay exemption; the caller-supplied comparison is the wider issue. |

#### HO-07: is_admin(), access-token hook, Edge Function admin checks

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | is_admin(), access-token hook, Edge Function admin checks |
| Description | Admin status is read from admin_roles without checking members.status, so a suspended administrator keeps admin rights in policies, RPCs, the member-field trigger bypass and Edge Functions. |
| Why it matters | Suspension is the main remedy for a compromised or departed administrator. |
| Evidence | supabase/migrations/20260321000003_authority_hardening_v2.sql:26-29<br>20260301000004_auth_hook.sql:17-18<br>supabase/functions/ingest-news/index.ts:70-88 |
| Reproduction approach | Local: suspend an admin with admin_set_member_status, then call an admin RPC with that user JWT after refresh. |
| Current status | POSSIBLY PRESENT |
| Recommended next step | Reproduce; then add a status join to is_admin(), the access-token hook and the Edge Function admin checks, with a negative pgTAP test. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-09: Storage bucket public

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | Storage bucket public |
| Description | Event images and project covers upload to a bucket named public that no migration creates and no storage policy covers; project creation continues silently without the image on failure. |
| Why it matters | Uploads probably fail in production; the 5 Sep report counted zero storage objects. |
| Evidence | app/admin/events.tsx:98-115<br>hooks/useCreateProject.ts:84-104<br>only bucket in migrations is uploads (20260321000003:261) |
| Reproduction approach | Device: create a project with a cover; admin creates an event with an image. Dashboard: check whether bucket public exists and its policies. |
| Current status | LIKELY FAILURE |
| Recommended next step | Confirm bucket state; move both paths to a defined bucket with folder-scoped policies in a migration. |
| Owner | Algene |
| Requires production test? | YES, read-only dashboard |
| Requires user decision? | NO |

#### HO-11: Media V1

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | Media V1 |
| Description | Media V1 does not exist beyond schema columns (media_type, duration_seconds, format_meta), a feed badge and an unused expo-av dependency. |
| Why it matters | Core sprint deliverable. |
| Evidence | supabase/migrations/20260707000005_content_media_types.sql<br>components/pulse/ArticleRow.tsx:31-78<br>package.json expo-av with no import |
| Reproduction approach | Search for a player, upload path or media bucket. |
| Current status | STILL PRESENT |
| Recommended next step | See 13. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-12: amari://auth-callback handler

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | amari://auth-callback handler |
| Description | Any URL containing auth-callback with access_token and refresh_token is turned into a session, from either the root deep-link handler or the auth-callback route. |
| Why it matters | A crafted link can sign a victim into an attacker-controlled account (login injection); the same URL may also be processed twice. |
| Evidence | lib/authCallback.ts:20-43<br>app/_layout.tsx:429-445<br>app/(auth)/auth-callback.tsx:12-30 |
| Reproduction approach | Device: open amari://auth-callback#access_token=...&refresh_token=... for a test account from another app. |
| Current status | POSSIBLY PRESENT |
| Recommended next step | Accept tokens only when a sign-in is pending (state or PKCE verifier), and handle the URL in one place. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-14: lib/sentry.ts

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | lib/sentry.ts |
| Description | The shim reads process.env.SENTRY_DSN; Expo only inlines EXPO_PUBLIC_ variables into the client bundle, so even with the SDK installed the DSN would be undefined. |
| Why it matters | A monitoring rollout could ship silently inert. |
| Evidence | lib/sentry.ts:22-23<br>.env.example |
| Reproduction approach | Build with the SDK and a DSN set as SENTRY_DSN; observe init. |
| Current status | STILL PRESENT |
| Recommended next step | Use EXPO_PUBLIC_SENTRY_DSN or app config extra. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-26: Open auth sign-up and the non-member actor

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | Open auth sign-up and the non-member actor |
| Description | The client creates auth users (email shouldCreateUser true; Apple and Google on first sign-in), so an authenticated account with no member row is a real actor class; every authenticated grant and policy must refuse it. |
| Why it matters | HO-01, HO-02 and HO-04 depend on it. |
| Evidence | app/(auth)/register.tsx:100<br>5 Sep report: three auth users without member rows |
| Reproduction approach | Create an auth user with no invitation; enumerate what it can read. |
| Current status | POSSIBLY PRESENT |
| Recommended next step | Add the non-member column to every row of 07 and test it. |
| Owner | Algene |
| Requires production test? | YES, read-only |
| Requires user decision? | YES, whether sign-up should be closed at the Auth level |

#### PR5-04: Google Play production access

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | Google Play production access |
| Description | Android has never been on Play production; the gate needs 12 testers opted in for 14 continuous days. 6 were opted in on 22 Sep. |
| Why it matters | Most of the intended audience uses Android. |
| Evidence | Owner memory of Play Console, 22 Sep 2026<br>5 Sep report |
| Reproduction approach | Play Console dashboard. |
| Current status | EXTERNAL VERIFICATION REQUIRED |
| Recommended next step | Owner chases opt-ins; Algene counts as one. |
| Owner | Jeremy |
| Requires production test? | N/A |
| Requires user decision? | NO |

#### PR5-06: get_news_feed

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | get_news_feed |
| Description | The feed scores every eligible article per call, sorts, and paginates with OFFSET; the hide anti-join and news_events have no retention. |
| Why it matters | Latency grows with members and events; OFFSET is unstable when scores move. |
| Evidence | supabase/migrations/20260718000001_reconcile_intelligence_release_schema.sql:151 onward |
| Reproduction approach | See 15 for the seeded load test. |
| Current status | STILL PRESENT |
| Recommended next step | Measure first; small index or keyset changes only in sprint. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-07: send-briefing-push and push generally

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | send-briefing-push and push generally |
| Description | Push chunks are posted sequentially in one invocation, with no receipt polling, so dead tokens are never pruned. |
| Why it matters | Timeouts at scale and Expo throttling as invalid tokens accumulate. |
| Evidence | supabase/functions/send-briefing-push/index.ts:112-121 |
| Reproduction approach | Dry run against synthetic tokens on staging. |
| Current status | STILL PRESENT |
| Recommended next step | Measure; add a receipt pass if small. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-09: request_account_deletion

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | request_account_deletion |
| Description | Account deletion only sets a flag and notifies; nothing deletes. |
| Why it matters | Store expectations and member trust. |
| Evidence | supabase/migrations/20260425000001_auth_review_and_account_deletion.sql:5 |
| Reproduction approach | Request deletion on a test identity; check what changes. |
| Current status | STILL PRESENT |
| Recommended next step | Owner decides automated job or documented service level. |
| Owner | Jeremy |
| Requires production test? | NO |
| Requires user decision? | YES |

#### PR5-10: pg_cron schedules

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | pg_cron schedules |
| Description | Only four cron jobs are defined in migrations; ingest, enrich, affinity fold, briefing push and project digest are registered only in production. |
| Why it matters | A rebuild from the repository comes up with the news pipeline and pushes silent. |
| Evidence | supabase/migrations/20260301000005_cron_jobs.sql<br>supabase/functions/NEWS-PIPELINE.md:45-95<br>docs/AMARI-WORKING-MEMORY.md:215-221 |
| Reproduction approach | Compare cron.job in production (read-only) with the four migration jobs. |
| Current status | STILL PRESENT |
| Recommended next step | One idempotent migration that reads the secret from Vault, never inlines it. |
| Owner | Algene |
| Requires production test? | YES, read-only |
| Requires user decision? | NO |

#### PR5-18: iOS Google Sign-In

| Field | Value |
|---|---|
| Severity | P1 |
| Surface | iOS Google Sign-In |
| Description | EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID absent from eas.json, so iOS uses the browser fallback. |
| Why it matters | Slower and more fragile path. |
| Evidence | lib/googleAuth.ts:30-33<br>eas.json |
| Reproduction approach | Device and EAS environment check. |
| Current status | EXTERNAL VERIFICATION REQUIRED |
| Recommended next step | Check EAS env; test both paths on device. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

### P2, fix soon or specify for Phase 2

#### HO-06: validate_invitation_code throttle

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | validate_invitation_code throttle |
| Description | Per-caller key falls back to x-forwarded-for, which the caller can influence; the global ceiling of 120 per minute lets anyone block all invitation validation. |
| Why it matters | Availability of onboarding; brute force bounded by the global ceiling. |
| Evidence | supabase/migrations/20260922000002_short_codes_and_validation_throttle.sql:103-165 |
| Reproduction approach | Local: 11 calls in 10 minutes from one key; 121 calls in a minute across spoofed keys. |
| Current status | APPARENTLY CHANGED, REVERIFY |
| Recommended next step | Prove both limits; decide whether a global lockout is acceptable. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |
| Notes | Client copy says wait an hour; window is 10 minutes (app/(auth)/invite.tsx:61). |

#### HO-08: get_member_tier()

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | get_member_tier() |
| Description | When the caller is not an active member, the function returns the tier from the JWT claim instead of refusing. |
| Why it matters | Stale or suspended sessions can carry a higher tier into any policy that does not also call is_active_member(). |
| Evidence | supabase/migrations/20260323000005_get_member_tier_prefers_db.sql:3-30 |
| Reproduction approach | Local: suspend a platinum member; with the old JWT call a policy that uses get_member_tier alone. |
| Current status | POSSIBLY PRESENT |
| Recommended next step | Audit every use; most pair it with is_active_member(). |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-10: Storage bucket uploads

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Storage bucket uploads |
| Description | Only the aligned-tiles folder has policies; there is no UPDATE policy; no file size or MIME limit is set in migrations; any active member can read any tile image. |
| Why it matters | Relevant to Media V1 design. |
| Evidence | supabase/migrations/20260321000003_authority_hardening_v2.sql:261-275 |
| Reproduction approach | Dashboard read of bucket settings. |
| Current status | STILL PRESENT |
| Recommended next step | Define limits when the media bucket is designed. |
| Owner | Algene |
| Requires production test? | YES, read-only |
| Requires user decision? | NO |

#### HO-13: Push tap routing from a killed app

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Push tap routing from a killed app |
| Description | Only addNotificationResponseReceivedListener is registered, inside the tabs layout after authentication; there is no last-response check on cold start. |
| Why it matters | Taps that launch the app may land on home instead of the target. |
| Evidence | lib/push.ts:64-76<br>app/(tabs)/_layout.tsx:8 |
| Reproduction approach | Device: kill the app, tap a briefing push. |
| Current status | REQUIRES DEVICE TEST |
| Recommended next step | Add a last-response check if confirmed. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-15: Edge Function authentication

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Edge Function authentication |
| Description | All pipeline and push functions share one secret header and are deployed without JWT verification; the admin fallback reads admin_roles only. |
| Why it matters | One leaked secret drives every function; HO-07 applies. |
| Evidence | supabase/functions/*/index.ts<br>supabase/functions/NEWS-PIPELINE.md:13-17 |
| Reproduction approach | Dashboard: function settings. |
| Current status | STILL PRESENT |
| Recommended next step | Document; rotate if exposure is suspected. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-18: .github/workflows/setup-keystore.yml

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | .github/workflows/setup-keystore.yml |
| Description | The one-off keystore workflow is still in the repository; it takes the keystore password as a workflow_dispatch input and uploads the keystore as an artefact. |
| Why it matters | Running it again would expose a new key the same way; the Feb 2026 run is recorded as potentially compromising the upload key. |
| Evidence | .github/workflows/setup-keystore.yml:1-40 |
| Reproduction approach | Read the workflow. |
| Current status | STILL PRESENT |
| Recommended next step | Delete the workflow; confirm Play App Signing so the upload key can be reset. |
| Owner | Jeremy |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-19: Owner workstation

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Owner workstation |
| Description | The Android upload keystore, its base64 copy and a .env with the Mapbox secret token sit untracked in the OneDrive-synced main checkout. |
| Why it matters | Cloud sync copies signing material off the machine. |
| Evidence | git check-ignore on the main checkout, 29 Sep 2026 (file presence only, contents not read) |
| Reproduction approach | n/a |
| Current status | OBSERVED |
| Recommended next step | Owner moves them; not an engineer task. |
| Owner | Jeremy |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-20: npm dependencies

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | npm dependencies |
| Description | npm audit --omit=dev reports 34 advisories (2 critical, 10 high) at 3ce4c4c; the 5 Sep report said 44 overall and none bundled. |
| Why it matters | Unknown bundle reach. |
| Evidence | npm audit on 29 Sep 2026 |
| Reproduction approach | Map each critical and high to runtime or build-only. |
| Current status | CANNOT VERIFY |
| Recommended next step | Map, do not mass-upgrade. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-23: Redemption failure path

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Redemption failure path |
| Description | If redeem_invitation_code errors, setup is marked complete, the guard finds no member row, alerts and signs the person out. |
| Why it matters | A network drop during sign-up strands the person. |
| Evidence | providers/AuthProvider.tsx:208-238<br>app/_layout.tsx:87-98 |
| Reproduction approach | Device: airplane mode immediately after the provider returns. |
| Current status | REQUIRES DEVICE TEST |
| Recommended next step | Fix copy and retry behaviour if confirmed. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-27: Aligned recent connections

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Aligned recent connections |
| Description | The card reads other members names from members, which RLS limits to the caller own row. |
| Why it matters | Names render empty. |
| Evidence | app/(tabs)/aligned/index.tsx:441-470 |
| Reproduction approach | Device with a mutual connection. |
| Current status | LIKELY FAILURE |
| Recommended next step | Use an RPC that returns the permitted fields. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-28: Logout and push token

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Logout and push token |
| Description | The push token stays on the member row after logout. |
| Why it matters | A shared or handed-on device keeps receiving the previous member pushes. |
| Evidence | lib/push.ts:47<br>no clearing code found |
| Reproduction approach | Device: log out, trigger a push to the old member. |
| Current status | POSSIBLY PRESENT |
| Recommended next step | Clear the token on sign-out. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-08: Member consent records

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Member consent records |
| Description | 21 of 23 members had no consent_given_at on 5 Sep. |
| Why it matters | Approved strategy makes consent a precondition for commercial data use. |
| Evidence | 5 Sep report<br>onboarding now writes consent_version (app/(onboarding)/index.tsx:35) |
| Reproduction approach | Read-only count in production. |
| Current status | CANNOT VERIFY |
| Recommended next step | Owner decides re-consent. |
| Owner | Jeremy |
| Requires production test? | YES, read-only count |
| Requires user decision? | YES |

#### PR5-11: Supabase legacy API keys

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Supabase legacy API keys |
| Description | The 5 Sep report states legacy anon and service-role JWT keys remain active alongside the new key system; the app ships the legacy anon key. |
| Why it matters | A leaked legacy service key is a long-lived full bypass. |
| Evidence | 5 Sep report<br>eas.json uses a JWT-format anon key |
| Reproduction approach | Dashboard API settings. |
| Current status | EXTERNAL VERIFICATION REQUIRED |
| Recommended next step | Plan migration to publishable keys; needs a store build. |
| Owner | Jeremy |
| Requires production test? | YES, dashboard |
| Requires user decision? | NO |

#### PR5-13: Jest suite

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Jest suite |
| Description | All 77 tests are pure logic in a node environment; three 1.2.5 tests assert source text; no component renders. |
| Why it matters | Automated passes say little about screens. |
| Evidence | jest.config.js<br>npm run test:ci on 29 Sep 2026: 10 suites, 77 tests pass |
| Reproduction approach | Run the suite. |
| Current status | STILL PRESENT |
| Recommended next step | Device matrix carries this sprint; add targeted tests for fixes. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-20: Query cache and session storage

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Query cache and session storage |
| Description | No query persistence (gcTime 5 minutes); session stored in SecureStore, which warns above 2 KB on Android. |
| Why it matters | Blank screens after offline resume; possible silent logout. |
| Evidence | lib/queryClient.ts:6-7<br>lib/supabase.ts:9-39 |
| Reproduction approach | Device: offline resume after 10 minutes; inspect stored session size. |
| Current status | REQUIRES DEVICE TEST |
| Recommended next step | Measure the session size on Android. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-23: Supabase plan, backups, PITR, pooling

| Field | Value |
|---|---|
| Severity | P2 |
| Surface | Supabase plan, backups, PITR, pooling |
| Description | Plan, backup schedule, point-in-time recovery and pooling have not been confirmed. |
| Why it matters | Recovery posture unknown. |
| Evidence | 5 Sep report |
| Reproduction approach | Dashboard. |
| Current status | EXTERNAL VERIFICATION REQUIRED |
| Recommended next step | Record in 14. |
| Owner | Jeremy |
| Requires production test? | YES, dashboard |
| Requires user decision? | NO |

### P3 and informational

#### HO-17: providers/AuthProvider.tsx types

| Field | Value |
|---|---|
| Severity | P3 |
| Surface | providers/AuthProvider.tsx types |
| Description | The MembershipTier type omits gold. |
| Why it matters | Type lies about data. |
| Evidence | providers/AuthProvider.tsx:7 |
| Reproduction approach | Read. |
| Current status | STILL PRESENT |
| Recommended next step | Fix when touching the file. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-21: README.md, CLAUDE.md, AGENTS.md, NEWS-PIPELINE.md

| Field | Value |
|---|---|
| Severity | P3 |
| Surface | README.md, CLAUDE.md, AGENTS.md, NEWS-PIPELINE.md |
| Description | Repository guidance says codes are 48 characters (now six), names an owner-machine worktree as the place to work, and tells operators to set an ignored OPENAI_MODEL. |
| Why it matters | Misleads new engineers and agents. |
| Evidence | README.md:12<br>CLAUDE.md:12<br>AGENTS.md:12 and 84-89<br>supabase/functions/NEWS-PIPELINE.md:34 |
| Reproduction approach | Read. |
| Current status | STILL PRESENT |
| Recommended next step | Update in the final handover PR. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-22: scripts/verify-security.mjs

| Field | Value |
|---|---|
| Severity | P3 |
| Surface | scripts/verify-security.mjs |
| Description | The security verifier never scans supabase/, where every authorisation finding lives. |
| Why it matters | CI green says nothing about SQL grants. |
| Evidence | scripts/verify-security.mjs:5 |
| Reproduction approach | Read. |
| Current status | STILL PRESENT |
| Recommended next step | Add pgTAP grant assertions as fixes land. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### HO-24: supabase/verification/p0

| Field | Value |
|---|---|
| Severity | P3 |
| Surface | supabase/verification/p0 |
| Description | The containment test suite and authorisation matrix SQL run only by hand; CI runs supabase/tests only. |
| Why it matters | Regressions in the 22 Sep controls would not fail CI. |
| Evidence | supabase/verification/p0/README.md<br>SECURITY-P0-CONTAINMENT record |
| Reproduction approach | Read ci.yml. |
| Current status | STILL PRESENT |
| Recommended next step | Promote replay-safe assertions into supabase/tests. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-14: components/TierGate.tsx

| Field | Value |
|---|---|
| Severity | P3 |
| Surface | components/TierGate.tsx |
| Description | Four-tier map without gold; unimported. |
| Why it matters | Wiring it would grant gold members platinum access. |
| Evidence | components/TierGate.tsx:6-7<br>no imports |
| Reproduction approach | grep imports. |
| Current status | STILL PRESENT |
| Recommended next step | Delete in a cleanup PR. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-15: lib/constants.ts and lib/theme.ts

| Field | Value |
|---|---|
| Severity | P3 |
| Surface | lib/constants.ts and lib/theme.ts |
| Description | Two token and tier files with differing labels. |
| Why it matters | Two sources of truth for tier-adjacent values. |
| Evidence | lib/constants.ts<br>lib/theme.ts:172-197 |
| Reproduction approach | Read both. |
| Current status | STILL PRESENT |
| Recommended next step | Phase 2. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-16: Dead surfaces

| Field | Value |
|---|---|
| Severity | P3 |
| Surface | Dead surfaces |
| Description | Corridor hidden at level 99; discover and network are empty stubs; components/pulse/IntelligenceFeed.tsx is unimported. |
| Why it matters | Noise. |
| Evidence | lib/theme.ts:195<br>app/(tabs)/_layout.tsx:26-27 |
| Reproduction approach | Read. |
| Current status | STILL PRESENT |
| Recommended next step | Owner decides Corridor. |
| Owner | Jeremy |
| Requires production test? | NO |
| Requires user decision? | YES |

#### PR5-19: News pipeline hygiene

| Field | Value |
|---|---|
| Severity | P3 |
| Surface | News pipeline hygiene |
| Description | Stale pending articles, three permanently failing sources, unpruned budget rows (5 Sep). |
| Why it matters | Noise that hides real failures. |
| Evidence | 5 Sep report |
| Reproduction approach | Read-only queries. |
| Current status | CANNOT VERIFY |
| Recommended next step | Measure in 14. |
| Owner | Algene |
| Requires production test? | YES, read-only |
| Requires user decision? | NO |

#### PR5-21: Store identity

| Field | Value |
|---|---|
| Severity | P3 |
| Surface | Store identity |
| Description | Apple seller shown as an individual; Play developer name is a placeholder; 17+ rating. |
| Why it matters | Brand and single point of failure. |
| Evidence | 5 Sep report<br>owner notes |
| Reproduction approach | Consoles. |
| Current status | EXTERNAL VERIFICATION REQUIRED |
| Recommended next step | Owner. |
| Owner | Jeremy |
| Requires production test? | NO |
| Requires user decision? | NO |

### Prior findings with fix evidence, retained for re-verification

#### PR5-01: map_projects, map_states, map_countries anon access

| Field | Value |
|---|---|
| Severity | Closed |
| Surface | map_projects, map_states, map_countries anon access |
| Description | Map functions were executable by anon without a membership gate (5 Sep, reproduced then). |
| Why it matters | n/a |
| Evidence | Live catalogue 22 Sep: anon=false, PUBLIC=false for all three (docs/evidence/after-20260922T011536Z-statement-one.csv)<br>guard assert_aligned_map_access at 20260921000001:378 |
| Reproduction approach | anon POST /rest/v1/rpc/map_projects must return 401 or permission denied. |
| Current status | FIXED WITH EVIDENCE |
| Recommended next step | Re-run the anon control once; see HO-01 for the table-level residual. |
| Owner | Algene |
| Requires production test? | YES, read-only |
| Requires user decision? | NO |

#### PR5-02: redeem_invitation_code identity binding

| Field | Value |
|---|---|
| Severity | Closed |
| Surface | redeem_invitation_code identity binding |
| Description | Function trusted caller-supplied p_user_id and was executable by PUBLIC and anon. |
| Why it matters | n/a |
| Evidence | Source 20260921000001:222-228 (identity_mismatch)<br>live 22 Sep: anon=false PUBLIC=false auth_uid=true |
| Reproduction approach | Call with another uid. |
| Current status | FIXED WITH EVIDENCE |
| Recommended next step | Re-run the negative once; residuals are HO-04 and HO-05. |
| Owner | Algene |
| Requires production test? | YES, read-only |
| Requires user decision? | NO |

#### PR5-03: validate_invitation_code oracle

| Field | Value |
|---|---|
| Severity | Closed |
| Surface | validate_invitation_code oracle |
| Description | No rate limit in front of 1,216 valid codes. |
| Why it matters | n/a |
| Evidence | 1,216 expired on 22 Sep (DEPLOYMENT_RECORD.md)<br>throttle in 20260922000002 |
| Reproduction approach | See HO-06. |
| Current status | APPARENTLY CHANGED, REVERIFY |
| Recommended next step | See HO-06. |
| Owner | Algene |
| Requires production test? | NO |
| Requires user decision? | NO |

#### PR5-12: Public repository

| Field | Value |
|---|---|
| Severity | Closed |
| Surface | Public repository |
| Description | Repository was public. |
| Why it matters | n/a |
| Evidence | gh repo view, 29 Sep 2026: PRIVATE |
| Reproduction approach | gh repo view. |
| Current status | FIXED WITH EVIDENCE |
| Recommended next step | Treat everything that was ever committed as public: the anon key, seed codes, the burned tester code. |
| Owner | Jeremy |
| Requires production test? | NO |
| Requires user decision? | NO |
