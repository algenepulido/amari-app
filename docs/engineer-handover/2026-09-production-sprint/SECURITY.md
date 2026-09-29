# Security

What earlier reviews found and whether it still holds, every current finding in one table, and an inventory of the database security surface. Commit `3ce4c4c`, 29 September 2026.

## Earlier findings reconciled

Commit `3ce4c4c`, 29 September 2026. This file reconciles every earlier readiness finding against
current code and then states one current baseline. It does not replace the earlier reports; they are
preserved where they are.

### Earlier reports found

| Report | Where | Finding IDs | Scope |
|---|---|---|---|
| "AMARI App Production Readiness", 5 September 2026, 21 pages | Owner's Downloads folder as a PDF; not in the repository. Built from release HEAD `6face8d` and live production SQL | None. The report uses headings and severity words only | Whole product, production data, stores |
| External reviewer threat model and authorisation matrix, 21 September 2026 | `docs/EXTERNAL_REVIEWER_THREAT_MODEL.md`, `docs/EXTERNAL_REVIEWER_AUTHORISATION_MATRIX.md` | Section-based | Invitation and reviewer access |
| P0 containment record, 22 September 2026 | `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`, `docs/evidence/` | Controls table | The stranger-to-admin chain |
| Security hardening roadmap | `docs/SECURITY-HARDENING-ROADMAP.md` | None | Older; line 25 still claims invite rate limiting as a foundation that was removed and later re-added differently |

Because the 5 September report carries no identifiers, this pack assigns `PR5-01` onward in the
order the report raises each finding, so later work can refer to them stably. New findings from
this inspection use `HO-` identifiers.

### Reconciliation of the 5 September report

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

### Reconciliation of the 21 and 22 September findings

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

### Numbers that moved

| Measure | Earlier figure | Current observed | Source of current figure |
|---|---|---|---|
| Tables | ~46 (brief), 46 (5 Sep), 47 app tables (21 Sep live) | 48 application tables defined in migrations, all with RLS enabled | Parser over 58 migrations at `3ce4c4c` |
| SECURITY DEFINER functions | ~60 (brief), 67 live on 21 Sep, 70 in the 21 Sep static parse | 65 application functions in source, matching the 22 Sep live catalogue's 68 minus 3 PostGIS `st_estimatedextent` overloads | Parser; `after-...statement-one.csv` |
| Migrations | 56 (5 Sep) | 58 | `supabase/migrations/` |
| Valid unused invitations | 1,216 (5 Sep) | 9 at 22 Sep, before the short-codes migration expired one more and before any later issuance | `DEPLOYMENT_RECORD.md` |

## Current findings

Ordered by severity. Each row has full evidence, reproduction steps, expected and actual behaviour, owner, and whether it needs a production check or an owner decision in `trackers/findings-register.csv`. "Closed" rows are earlier findings with fix evidence, kept so they are re-verified once.

| ID | Severity | Surface | Finding | Status | Next step |
|---|---|---|---|---|---|
| HO-01 | P0 | map_cache_projects, map_cache_states, map_cache_countries | The three map cache tables have SELECT policies USING (true) for authenticated, so any signed-in account, including one with no member row, can read project names, descriptions, creator first names, image URLs, external links and coordinates, bypassing the gold gate added to the map functions on 22 Sep. | POSSIBLY PRESENT | Confirm live policy and grants read-only. Fix by gating the policy on is_active_member() and tier, and update the two client reads in the same PR. |
| HO-04 | P0 | redeem_invitation_code | Redemption has no throttle, so it is a second, unthrottled oracle for the six-character invitation codes introduced on 22 Sep. | POSSIBLY PRESENT | Reproduce locally, then add a per-auth-user attempt limit inside redeem and a pgTAP test that the Nth attempt is refused. Confirm live body matches source. |
| HO-16 | P0 | All EAS profiles and Supabase | No staging or test environment exists; every build profile targets the production Supabase project. | STILL PRESENT | Owner chooses local-only, staging project, or branching (04). Algene then adds an EAS profile if staging is chosen. |
| HO-25 | P0 | rsvp_to_event | For events with a capacity, a first-time RSVP appears to write no row while returning success. | LIKELY FAILURE | Reproduce first. Fix by testing v_existing.id rather than FOUND, add a pgTAP test for first-time RSVP with and without capacity. |
| PR5-05 | P0 | Mobile app | No crash or error reporting is installed; lib/sentry.ts and lib/posthog.ts are guarded no-op shims and lib/reportError.ts writes to console.error. | STILL PRESENT | Install @sentry/react-native with its Expo plugin, use an EXPO_PUBLIC_ DSN name, upload source maps from EAS, prove a deliberate error from a release-profile build. |
| HO-02 | P1 | projects SELECT policy | Approved projects are readable by any authenticated account; the policy has no is_active_member() or tier condition. | POSSIBLY PRESENT | Confirm live; align with the HO-01 decision. |
| HO-03 | P1 | projects creator policy | The creator policy is FOR ALL with USING (auth.uid() = creator_id) and no WITH CHECK or status guard, so a creator appears able to update their own project status to approved without admin review. | POSSIBLY PRESENT | Reproduce; split the policy into insert and update with a check that status stays pending for non-admins, or add a trigger. |
| HO-05 | P1 | redeem_invitation_code recipient binding | The recipient-email check compares the caller-supplied p_email, not the signed-in account email, and exempts any address ending privaterelay.appleid.com. | STILL PRESENT | Read the email from auth.users for auth.uid() inside the function; decide the Apple relay policy with the owner. |
| HO-07 | P1 | is_admin(), access-token hook, Edge Function admin checks | Admin status is read from admin_roles without checking members.status, so a suspended administrator keeps admin rights in policies, RPCs, the member-field trigger bypass and Edge Functions. | POSSIBLY PRESENT | Reproduce; then add a status join to is_admin(), the access-token hook and the Edge Function admin checks, with a negative pgTAP test. |
| HO-09 | P1 | Storage bucket public | Event images and project covers upload to a bucket named public that no migration creates and no storage policy covers; project creation continues silently without the image on failure. | LIKELY FAILURE | Confirm bucket state; move both paths to a defined bucket with folder-scoped policies in a migration. |
| HO-11 | P1 | Media V1 | Media V1 does not exist beyond schema columns (media_type, duration_seconds, format_meta), a feed badge and an unused expo-av dependency. | STILL PRESENT | See 13. |
| HO-12 | P1 | amari://auth-callback handler | Any URL containing auth-callback with access_token and refresh_token is turned into a session, from either the root deep-link handler or the auth-callback route. | POSSIBLY PRESENT | Accept tokens only when a sign-in is pending (state or PKCE verifier), and handle the URL in one place. |
| HO-14 | P1 | lib/sentry.ts | The shim reads process.env.SENTRY_DSN; Expo only inlines EXPO_PUBLIC_ variables into the client bundle, so even with the SDK installed the DSN would be undefined. | STILL PRESENT | Use EXPO_PUBLIC_SENTRY_DSN or app config extra. |
| HO-26 | P1 | Open auth sign-up and the non-member actor | The client creates auth users (email shouldCreateUser true; Apple and Google on first sign-in), so an authenticated account with no member row is a real actor class; every authenticated grant and policy must refuse it. | POSSIBLY PRESENT | Add the non-member column to every row of 07 and test it. |
| PR5-04 | P1 | Google Play production access | Android has never been on Play production; the gate needs 12 testers opted in for 14 continuous days. 6 were opted in on 22 Sep. | EXTERNAL VERIFICATION REQUIRED | Owner chases opt-ins; Algene counts as one. |
| PR5-06 | P1 | get_news_feed | The feed scores every eligible article per call, sorts, and paginates with OFFSET; the hide anti-join and news_events have no retention. | STILL PRESENT | Measure first; small index or keyset changes only in sprint. |
| PR5-07 | P1 | send-briefing-push and push generally | Push chunks are posted sequentially in one invocation, with no receipt polling, so dead tokens are never pruned. | STILL PRESENT | Measure; add a receipt pass if small. |
| PR5-09 | P1 | request_account_deletion | Account deletion only sets a flag and notifies; nothing deletes. | STILL PRESENT | Owner decides automated job or documented service level. |
| PR5-10 | P1 | pg_cron schedules | Only four cron jobs are defined in migrations; ingest, enrich, affinity fold, briefing push and project digest are registered only in production. | STILL PRESENT | One idempotent migration that reads the secret from Vault, never inlines it. |
| PR5-18 | P1 | iOS Google Sign-In | EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID absent from eas.json, so iOS uses the browser fallback. | EXTERNAL VERIFICATION REQUIRED | Check EAS env; test both paths on device. |
| HO-06 | P2 | validate_invitation_code throttle | Per-caller key falls back to x-forwarded-for, which the caller can influence; the global ceiling of 120 per minute lets anyone block all invitation validation. | APPARENTLY CHANGED, REVERIFY | Prove both limits; decide whether a global lockout is acceptable. |
| HO-08 | P2 | get_member_tier() | When the caller is not an active member, the function returns the tier from the JWT claim instead of refusing. | POSSIBLY PRESENT | Audit every use; most pair it with is_active_member(). |
| HO-10 | P2 | Storage bucket uploads | Only the aligned-tiles folder has policies; there is no UPDATE policy; no file size or MIME limit is set in migrations; any active member can read any tile image. | STILL PRESENT | Define limits when the media bucket is designed. |
| HO-13 | P2 | Push tap routing from a killed app | Only addNotificationResponseReceivedListener is registered, inside the tabs layout after authentication; there is no last-response check on cold start. | REQUIRES DEVICE TEST | Add a last-response check if confirmed. |
| HO-15 | P2 | Edge Function authentication | All pipeline and push functions share one secret header and are deployed without JWT verification; the admin fallback reads admin_roles only. | STILL PRESENT | Document; rotate if exposure is suspected. |
| HO-18 | P2 | .github/workflows/setup-keystore.yml | The one-off keystore workflow is still in the repository; it takes the keystore password as a workflow_dispatch input and uploads the keystore as an artefact. | STILL PRESENT | Delete the workflow; confirm Play App Signing so the upload key can be reset. |
| HO-19 | P2 | Owner workstation | The Android upload keystore, its base64 copy and a .env with the Mapbox secret token sit untracked in the OneDrive-synced main checkout. | OBSERVED | Owner moves them; not an engineer task. |
| HO-20 | P2 | npm dependencies | npm audit --omit=dev reports 34 advisories (2 critical, 10 high) at 3ce4c4c; the 5 Sep report said 44 overall and none bundled. | CANNOT VERIFY | Map, do not mass-upgrade. |
| HO-23 | P2 | Redemption failure path | If redeem_invitation_code errors, setup is marked complete, the guard finds no member row, alerts and signs the person out. | REQUIRES DEVICE TEST | Fix copy and retry behaviour if confirmed. |
| HO-27 | P2 | Aligned recent connections | The card reads other members names from members, which RLS limits to the caller own row. | LIKELY FAILURE | Use an RPC that returns the permitted fields. |
| HO-28 | P2 | Logout and push token | The push token stays on the member row after logout. | POSSIBLY PRESENT | Clear the token on sign-out. |
| PR5-08 | P2 | Member consent records | 21 of 23 members had no consent_given_at on 5 Sep. | CANNOT VERIFY | Owner decides re-consent. |
| PR5-11 | P2 | Supabase legacy API keys | The 5 Sep report states legacy anon and service-role JWT keys remain active alongside the new key system; the app ships the legacy anon key. | EXTERNAL VERIFICATION REQUIRED | Plan migration to publishable keys; needs a store build. |
| PR5-13 | P2 | Jest suite | All 77 tests are pure logic in a node environment; three 1.2.5 tests assert source text; no component renders. | STILL PRESENT | Device matrix carries this sprint; add targeted tests for fixes. |
| PR5-20 | P2 | Query cache and session storage | No query persistence (gcTime 5 minutes); session stored in SecureStore, which warns above 2 KB on Android. | REQUIRES DEVICE TEST | Measure the session size on Android. |
| PR5-23 | P2 | Supabase plan, backups, PITR, pooling | Plan, backup schedule, point-in-time recovery and pooling have not been confirmed. | EXTERNAL VERIFICATION REQUIRED | Record in 14. |
| HO-17 | P3 | providers/AuthProvider.tsx types | The MembershipTier type omits gold. | STILL PRESENT | Fix when touching the file. |
| HO-21 | P3 | README.md, CLAUDE.md, AGENTS.md, NEWS-PIPELINE.md | Repository guidance says codes are 48 characters (now six), names an owner-machine worktree as the place to work, and tells operators to set an ignored OPENAI_MODEL. | STILL PRESENT | Update in the final handover PR. |
| HO-22 | P3 | scripts/verify-security.mjs | The security verifier never scans supabase/, where every authorisation finding lives. | STILL PRESENT | Add pgTAP grant assertions as fixes land. |
| HO-24 | P3 | supabase/verification/p0 | The containment test suite and authorisation matrix SQL run only by hand; CI runs supabase/tests only. | STILL PRESENT | Promote replay-safe assertions into supabase/tests. |
| PR5-14 | P3 | components/TierGate.tsx | Four-tier map without gold; unimported. | STILL PRESENT | Delete in a cleanup PR. |
| PR5-15 | P3 | lib/constants.ts and lib/theme.ts | Two token and tier files with differing labels. | STILL PRESENT | Phase 2. |
| PR5-16 | P3 | Dead surfaces | Corridor hidden at level 99; discover and network are empty stubs; components/pulse/IntelligenceFeed.tsx is unimported. | STILL PRESENT | Owner decides Corridor. |
| PR5-19 | P3 | News pipeline hygiene | Stale pending articles, three permanently failing sources, unpruned budget rows (5 Sep). | CANNOT VERIFY | Measure in 14. |
| PR5-21 | P3 | Store identity | Apple seller shown as an individual; Play developer name is a placeholder; 17+ rating. | EXTERNAL VERIFICATION REQUIRED | Owner. |
| PR5-01 | Closed | map_projects, map_states, map_countries anon access | Map functions were executable by anon without a membership gate (5 Sep, reproduced then). | FIXED WITH EVIDENCE | Re-run the anon control once; see HO-01 for the table-level residual. |
| PR5-02 | Closed | redeem_invitation_code identity binding | Function trusted caller-supplied p_user_id and was executable by PUBLIC and anon. | FIXED WITH EVIDENCE | Re-run the negative once; residuals are HO-04 and HO-05. |
| PR5-03 | Closed | validate_invitation_code oracle | No rate limit in front of 1,216 valid codes. | APPARENTLY CHANGED, REVERIFY | See HO-06. |
| PR5-12 | Closed | Public repository | Repository was public. | FIXED WITH EVIDENCE | Treat everything that was ever committed as public: the anon key, seed codes, the burned tester code. |

## Database security inventory

Static inventory of the 58 migrations at commit `3ce4c4c`, cross-checked against the production
catalogue captured on 22 September 2026 at 01:14 UTC (`docs/evidence/after-20260922T011536Z-statement-one.csv`).
Nothing here was read from the live database during preparation of this pack.

**Method.** A parser split every migration into statements (respecting dollar quoting), applied
them in filename order with last definition winning, and tracked tables, RLS, policies, functions,
grants, triggers, buckets and cron calls. It also catches RLS enabled through dynamic `execute`
inside `do` blocks. Line numbers point at the statement start. The parser is not a PostgreSQL
engine: treat it as an index into the files, and treat the live catalogue as the authority.

### Counts

| Object | Current, from migrations | Live, 22 Sep 2026 | Earlier estimate |
|---|---|---|---|
| Migration files | 58 (`20260301000000` to `20260922000002`) | 55 applied at 21 Sep, before the three September migrations | 56 on 5 Sep |
| Application tables in `public` | 48 | 48 including PostGIS `spatial_ref_sys`, so 47 application tables. The difference is `external_tester_access`, whose migration had not run at capture time | About 46 |
| Views | 0 | Not captured | |
| Materialised views | 0 | Not captured | |
| Tables with RLS enabled | 48 of 48 | 47 of 47 application tables; `spatial_ref_sys` has RLS off (PostGIS system table) | |
| Tables with RLS and no policy (deny all app roles) | 14 | 13 (no `external_tester_access`) | |
| RLS policies on `public` tables | 57 | 57 | |
| Storage policies on `storage.objects` | 3 | Not captured | |
| Functions in `public` defined by the application | 78 | 799 total in `public`, most from PostGIS | |
| SECURITY DEFINER | 65 | 68, of which 3 are PostGIS `st_estimatedextent` overloads, so 65 application | About 60 |
| SECURITY INVOKER | 13 | Not broken out | |
| SECURITY DEFINER with PUBLIC execute | Not derivable from source reliably | 10 (7 application, 3 PostGIS) | 15 on 21 Sep |
| SECURITY DEFINER with anon execute | | 11 (8 application, 3 PostGIS) | 16 on 21 Sep |
| SECURITY DEFINER without `search_path` | 2 (`check_rate_limit`, `generate_weekly_matches`) | 5 (the same 2 plus 3 PostGIS) | 8 on 21 Sep |
| Triggers | 11 | Not captured | |
| Storage buckets in migrations | 1 (`uploads`, private) | Not captured. The client also writes to `public`, which no migration creates (HO-09) | |
| Cron jobs in migrations | 4 | 9 active on 5 Sep per report | |

The live figures for PUBLIC and anon predate `20260922000001` and `20260922000002`. The second
re-revoked `generate_share_invite_code` from all application roles and re-granted
`validate_invitation_code` to anon and authenticated only. Neither changes the counts above.

### Tables

| Table | Policies | Notes |
|---|---|---|
| `admin_roles` | 1 | Self or admin read. Written only by `redeem_invitation_code` |
| `aligned_history`, `aligned_reports` | 0 | Deny all. No member write path for reports exists (see `FEATURES.md`) |
| `aligned_interests`, `aligned_matches`, `aligned_skips`, `aligned_tiles` | 2, 2, 2, 3 | `aligned_tiles_own_crud` USING lacks `is_active_member()` |
| `barcode_revocations`, `barcode_seeds` | 1, 0 | |
| `city_presence`, `connections` | 2, 1 | `connections_read_own` lacks `is_active_member()` |
| `corridor_interests`, `corridor_opportunities` | 3, 2 | Surface hidden in client |
| `dead_letter_queue`, `rate_limits` | 0 | RLS via dynamic SQL at `20260321000003:279-280` |
| `event_rsvps`, `events` | 2, 2 | |
| `external_tester_access` | 0 | Added `20260922000001`; applied to production is EXTERNAL VERIFICATION REQUIRED |
| `invitation_codes` | 1 | Admin only. Plaintext `code` column still populated on every row at 22 Sep |
| `invitation_expiry_backup_20260921` | 0, forced RLS | Rollback data from containment |
| `issue_reports` | 3 | |
| `map_cache_countries`, `map_cache_projects`, `map_cache_states` | 1 each | `USING (true)` to authenticated (HO-01) |
| `member_entity_follows`, `member_feed_interests`, `member_monthly_invites` | 1, 1, 2 | |
| `member_onboarding_evidence_ledger`, `member_onboarding_responses`, `member_onboarding_snapshots` | 0, 1, 1 | |
| `members` | 3 | Self read, self update guarded by trigger, admin all |
| `news_ai_budget_reservations`, `news_ai_spend`, `news_pipeline_leases`, `news_sources` | 0 | Pipeline internal |
| `news_articles`, `news_events` | 1, 1 | |
| `notifications` | 2 | |
| `project_bookmarks` | 1 | Policy has no role, so it applies to `public`; relies on `auth.uid()` |
| `project_contact_requests` | 0 | RPC access only |
| `project_updates` | 3 | |
| `projects` | 3 | `Creators can manage own projects` is FOR ALL without a status guard (HO-03); approved rows readable by any authenticated (HO-02) |
| `pulse_editions` | 1 | Admin only; members read via RPC |
| `push_log` | 0 | |
| `region_centroids` | 1 | Reference data, all authenticated |
| `saved_articles` | 1 | Lacks `is_active_member()` |
| `tier_changes` | 3 | |
| `tracked_entities` | 1 | |

Full policy text with file and line is in `trackers/authorisation-matrix.csv`, column `CURRENT_POLICY_EVIDENCE`.

### Triggers

| Trigger | Table | Function | Defined at |
|---|---|---|---|
| `project_enforce_region_privacy` | `projects` | `enforce_project_region_privacy` | `20260326000004:62` |
| `project_set_display_point` | `projects` | `set_project_display_point` | `20260326000001:269` |
| `projects_updated_at` | `projects` | `update_projects_updated_at` | `20260326000001:283` |
| `tr_apply_aligned_tile_submission_defaults` | `aligned_tiles` | SECURITY DEFINER, PUBLIC execute | `20260323000001:660` |
| `tr_events_updated` | `events` | `update_timestamp` | `20260301000000:187` |
| `tr_issue_notify` | `issue_reports` | `notify_admins_of_issue`, pg_net, Vault | `20260710000006:113` |
| `tr_member_display_id` | `members` | `set_member_display_id` | `20260301000000:100` |
| `tr_members_updated` | `members` | `update_timestamp` | `20260301000000:112` |
| `tr_pcr_notify` | `project_contact_requests` | `notify_project_engagement`, pg_net, Vault | `20260710000005:144` |
| `tr_prevent_privileged_member_field_updates` | `members` | Blocks self changes to tier, status, display id, inviter, consent, `onboarded_at` | `20260321000003:62` |
| `tr_pulse_updated` | `pulse_editions` | `update_timestamp` | `20260301000000:159` |

### Storage

| Bucket | Public? | Policies | Used by |
|---|---|---|---|
| `uploads` | No (`20260321000003:261`) | Insert own folder `aligned-tiles/<uid>/` for active members (273); delete own (274); select `aligned-tiles/*` for active members (275). No UPDATE policy | `hooks/useCreateTile.ts:61` |
| `public` | Unknown | None in migrations | `app/admin/events.tsx:104`, `hooks/useCreateProject.ts:90`, via `getPublicUrl()` |

File size limits and allowed MIME types are not set in any migration; if they exist they are
dashboard settings (EXTERNAL VERIFICATION REQUIRED). The storage path assumption "only gold and
above see project imagery" is not enforced anywhere: the `public` bucket, if it exists and is
public, serves images to anyone with the URL, and `map_cache_projects.image_url` hands that URL to
any authenticated caller.

### Scheduled jobs in version control

| Job | Schedule | Action | Defined at |
|---|---|---|---|
| `generate-aligned-matches` | `0 19 * * 0` | `generate_weekly_matches()` | `20260301000005_cron_jobs.sql:6` |
| `generate-daily-seed` | `0 14 * * *` | `ensure_daily_seed()` | `:13` |
| `cleanup-rate-limits` | `*/15 * * * *` | `cleanup_rate_limits()` | `:20` |
| `expire-aligned-matches` | `0 0 * * *` | match expiry | `:27` |

Not in version control but running in production per the 5 September report and
`supabase/functions/NEWS-PIPELINE.md:45-95`: news ingest (about :05 and :50), enrich (about :15 and
:45), affinity fold (nightly), briefing push, project engagement digest. Exact schedules are
EXTERNAL VERIFICATION REQUIRED (`select jobname, schedule, command from cron.job`, which returns
commands that may embed secrets; read with care and never paste the output).

### Flags the brief asked for

- **PUBLIC execute grants.** Live at 22 Sep: `get_member_tier`, `is_active_member`, `is_admin` (helpers used inside policies; they return false or `member` for anon) and four trigger functions (`apply_aligned_tile_submission_defaults`, `notify_admins_of_issue`, `notify_project_engagement`, `prevent_privileged_member_field_updates`). Prove a direct call to each trigger function fails outside trigger context.
- **Insufficient `auth.uid()` checks.** Every function reachable by `authenticated` references `auth.uid()` or `is_active_member()` except the map trio (which call `assert_aligned_map_access`), `get_pulse_feed` and `get_pulse_edition` (which call `is_active_member()`). The residual risk is the non-member actor: a function that checks only `auth.uid() is not null` admits anyone who has created an auth account (HO-26).
- **Caller-supplied user IDs.** `redeem_invitation_code` (asserted against `auth.uid()`), `rsvp_to_event` (asserted), `aligned_decide`, `generate_barcode_token`, `get_admin_role`, `admin_set_member_status` and `change_member_tier` (admin targets by design; `p_changed_by` is caller supplied). Each needs a negative test with another member's id.
- **Caller-supplied identity other than ids.** `redeem_invitation_code.p_email` (HO-05); `validate_invitation_code` keys its throttle on `x-forwarded-for` when anonymous (HO-06).
- **Stale tier and admin claims.** The hook stamps claims at token mint (`20260301000004_auth_hook.sql:17-24`); the default access-token lifetime is one hour unless the dashboard says otherwise (EXTERNAL). Server checks mostly read tables, so staleness matters mainly for client navigation and for `get_member_tier()`'s JWT fallback (HO-08). `is_admin()` and the hook ignore suspension (HO-07).
- **Mutable `search_path`.** `check_rate_limit` and `generate_weekly_matches` have none; both are service role only at 22 Sep.
- **Functions that bypass RLS.** All 65 SECURITY DEFINER functions run as `postgres` and bypass RLS by construction; the table below records what each checks instead.
- **Dynamic SQL.** None detected inside SECURITY DEFINER bodies. The only dynamic `execute` statements found enable RLS in a migration `do` block.
- **Storage assumptions that differ from database permissions.** See the storage section above and HO-01, HO-09, HO-10.

### SECURITY DEFINER functions

All 65, with live grants, checks, search_path, risk notes and test coverage: `reference/security-definer-functions.md`. Turn each row into a CI pgTAP assertion as fixes land: a grant check for anon, authenticated and PUBLIC, and a behavioural check run as a real `authenticated` JWT for an allowed and a refused actor. Never use the service role as evidence that a policy works.
