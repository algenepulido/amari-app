# Database security inventory

Static inventory of the 58 migrations at commit `3ce4c4c`, cross-checked against the production
catalogue captured on 22 September 2026 at 01:14 UTC (`docs/evidence/after-20260922T011536Z-statement-one.csv`).
Nothing here was read from the live database during preparation of this pack.

**Method.** A parser split every migration into statements (respecting dollar quoting), applied
them in filename order with last definition winning, and tracked tables, RLS, policies, functions,
grants, triggers, buckets and cron calls. It also catches RLS enabled through dynamic `execute`
inside `do` blocks. Line numbers point at the statement start. The parser is not a PostgreSQL
engine: treat it as an index into the files, and treat the live catalogue as the authority.

## Counts

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

## Tables

| Table | Policies | Notes |
|---|---|---|
| `admin_roles` | 1 | Self or admin read. Written only by `redeem_invitation_code` |
| `aligned_history`, `aligned_reports` | 0 | Deny all. No member write path for reports exists (see `05`) |
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

Full policy text with file and line is in `07_AUTHORIZATION_MATRIX_STARTER.csv`, column `CURRENT_POLICY_EVIDENCE`.

## Triggers

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

## Storage

| Bucket | Public? | Policies | Used by |
|---|---|---|---|
| `uploads` | No (`20260321000003:261`) | Insert own folder `aligned-tiles/<uid>/` for active members (273); delete own (274); select `aligned-tiles/*` for active members (275). No UPDATE policy | `hooks/useCreateTile.ts:61` |
| `public` | Unknown | None in migrations | `app/admin/events.tsx:104`, `hooks/useCreateProject.ts:90`, via `getPublicUrl()` |

File size limits and allowed MIME types are not set in any migration; if they exist they are
dashboard settings (EXTERNAL VERIFICATION REQUIRED). The storage path assumption "only gold and
above see project imagery" is not enforced anywhere: the `public` bucket, if it exists and is
public, serves images to anyone with the URL, and `map_cache_projects.image_url` hands that URL to
any authenticated caller.

## Scheduled jobs in version control

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

## Flags the brief asked for

- **PUBLIC execute grants.** Live at 22 Sep: `get_member_tier`, `is_active_member`, `is_admin` (helpers used inside policies; they return false or `member` for anon) and four trigger functions (`apply_aligned_tile_submission_defaults`, `notify_admins_of_issue`, `notify_project_engagement`, `prevent_privileged_member_field_updates`). Prove a direct call to each trigger function fails outside trigger context.
- **Insufficient `auth.uid()` checks.** Every function reachable by `authenticated` references `auth.uid()` or `is_active_member()` except the map trio (which call `assert_aligned_map_access`), `get_pulse_feed` and `get_pulse_edition` (which call `is_active_member()`). The residual risk is the non-member actor: a function that checks only `auth.uid() is not null` admits anyone who has created an auth account (HO-26).
- **Caller-supplied user IDs.** `redeem_invitation_code` (asserted against `auth.uid()`), `rsvp_to_event` (asserted), `aligned_decide`, `generate_barcode_token`, `get_admin_role`, `admin_set_member_status` and `change_member_tier` (admin targets by design; `p_changed_by` is caller supplied). Each needs a negative test with another member's id.
- **Caller-supplied identity other than ids.** `redeem_invitation_code.p_email` (HO-05); `validate_invitation_code` keys its throttle on `x-forwarded-for` when anonymous (HO-06).
- **Stale tier and admin claims.** The hook stamps claims at token mint (`20260301000004_auth_hook.sql:17-24`); the default access-token lifetime is one hour unless the dashboard says otherwise (EXTERNAL). Server checks mostly read tables, so staleness matters mainly for client navigation and for `get_member_tier()`'s JWT fallback (HO-08). `is_admin()` and the hook ignore suspension (HO-07).
- **Mutable `search_path`.** `check_rate_limit` and `generate_weekly_matches` have none; both are service role only at 22 Sep.
- **Functions that bypass RLS.** All 65 SECURITY DEFINER functions run as `postgres` and bypass RLS by construction; the table below records what each checks instead.
- **Dynamic SQL.** None detected inside SECURITY DEFINER bodies. The only dynamic `execute` statements found enable RLS in a migration `do` block.
- **Storage assumptions that differ from database permissions.** See the storage section above and HO-01, HO-09, HO-10.

## SECURITY DEFINER functions

Generated from the parser output and the 22 Sep catalogue. "Auth check" means the body references
`auth.uid()`. "Role or tier check" is a text signal (`is_admin`, `admin_roles`,
`is_active_member`, tier logic) and must be confirmed by reading the body. CI tests run on every
push; `supabase/verification/p0` does not.

| Function | Purpose | Execute grants, live 22 Sep | Auth check | Role or tier check | search_path | Dynamic SQL | Risk notes | Test coverage | Defined at |
|---|---|---|---|---|---|---|---|---|---|
| `acknowledge_monthly_invite_announcement` | Member dismisses the monthly invite announcement | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no |  | none found | `20260323000001_membership_invites_and_moderation.sql:286` |
| `admin_create_invitation_code` | Admin issues an invitation code (Admin Codes screen) | PUBLIC=false anon=false auth=true | auth.uid() | admin | public, extensions | no |  | none found | `20260710000002_gold_tier_functions.sql:56` |
| `admin_set_member_status` | Admin suspends or reactivates a member | PUBLIC=false anon=false auth=true | auth.uid() | admin | public | no | Takes p_member_id by design (admin target). Verify it also removes or neutralises admin_roles on suspension (HO-07). | none found | `20260504000002_admin_member_operations.sql:7` |
| `admin_set_project_status` | Admin approves or rejects a project | PUBLIC=false anon=false auth=true | auth.uid() | admin | public | no |  | none found | `20260504000006_admin_project_review.sql:14` |
| `aligned_decide` | Member accepts or skips a weekly Aligned match | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no | Takes optional p_member_id; verify it is asserted against auth.uid(). | none found | `20260322000001_aligned_contract_repairs.sql:4` |
| `aligned_discovery_tiles` | Returns Aligned discovery tiles for the caller | PUBLIC=false anon=false auth=true | auth.uid() | active member, tier logic | public | no |  | none found | `20260323000002_external_project_contact.sql:22` |
| `aligned_express_interest` | Member expresses interest in an Aligned tile | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | none found | `20260323000001_membership_invites_and_moderation.sql:785` |
| `append_article_entity` | News pipeline tags an article with a tracked entity | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | none found | `20260710000003_tracked_entities.sql:164` |
| `apply_aligned_tile_submission_defaults` | Trigger: sets moderation defaults on tile insert | PUBLIC=true anon=true auth=true | none in body | none detected | public | no | Trigger function with PUBLIC execute. | none found | `20260323000001_membership_invites_and_moderation.sql:624` |
| `assert_aligned_map_access` | Guard used by map functions: active member at gold or above | PUBLIC=false anon=false auth=false | auth.uid() | admin | public | no |  | none found | `20260921000001_p0_invitation_containment.sql:378` |
| `cancel_event_rsvp` | Member cancels own event RSVP | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no |  | none found | `20260707000002_event_ticketing.sql:77` |
| `change_member_tier` | Admin changes a member tier and records tier_changes | PUBLIC=false anon=false auth=true | auth.uid() | admin, tier logic | public | no | p_changed_by is caller supplied; verify it is ignored in favour of auth.uid() for audit integrity. | supabase/verification/p0 (manual, not in CI) | `20260321000003_authority_hardening_v2.sql:183` |
| `check_rate_limit` | Legacy rate limit helper, now service role only | PUBLIC=false anon=false auth=false | none in body | none detected | NOT SET | no | No search_path. Service role only since containment. Called by nothing live. | supabase/verification/p0 (manual, not in CI) | `20260301000000_initial_schema.sql:633` |
| `connect_with_member_barcode` | Member scans another member pass to connect | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public, extensions | no |  | none found | `20260504000001_qr_member_connections.sql:11` |
| `create_monthly_invite` | Member creates a monthly invite for a guest | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public, extensions | no |  | none found | `20260323000006_monthly_invite_code_normalization.sql:27` |
| `ensure_daily_seed` | Cron: daily seed for Aligned rotation | PUBLIC=false anon=false auth=false | none in body | none detected | public, extensions | no |  | none found | `20260321000003_authority_hardening_v2.sql:129` |
| `fold_feed_affinities` | Nightly fold of engagement into learned feed weights | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | none found | `20260707000001_intelligence_feed.sql:395` |
| `generate_barcode_token` | Issues the member pass barcode token | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public, extensions | no | Takes optional p_member_id; verify it cannot mint another member pass. | none found | `20260321000003_authority_hardening_v2.sql:138` |
| `generate_share_invite_code` | Generates six character Crockford invitation codes | PUBLIC=false anon=false auth=false (re-revoked from all app roles in 20260922000002) | none in body | none detected | public, extensions | no |  | supabase/verification/p0 (manual, not in CI) | `20260922000002_short_codes_and_validation_throttle.sql:46` |
| `generate_weekly_matches` | Cron: weekly Aligned matching | PUBLIC=false anon=false auth=false | none in body | none detected | NOT SET | no | No search_path. Service role and cron only. Scale behaviour unmeasured. | none found | `20260301000000_initial_schema.sql:511` |
| `get_admin_role` | Returns admin role for a member | PUBLIC=false anon=false auth=true | auth.uid() | admin | public | no | Takes p_member_id defaulting to auth.uid(); verify non-admins cannot query others. | none found | `20260323000001_membership_invites_and_moderation.sql:15` |
| `get_aligned_connections` | Returns caller connections for Aligned | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | none found | `20260322000001_aligned_contract_repairs.sql:275` |
| `get_aligned_tile_contact_details` | Reveals tile contact after mutual consent | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | none found | `20260323000002_external_project_contact.sql:90` |
| `get_event_checkin_stats` | Admin check-in statistics for an event | PUBLIC=false anon=false auth=true | auth.uid() | admin | public | no |  | none found | `20260707000002_event_ticketing.sql:97` |
| `get_member_tier` | Caller tier, database first, JWT claim fallback | PUBLIC=true anon=true auth=true | auth.uid() | tier logic | public | no | Falls back to the JWT tier claim when the caller is not an active member (HO-08). PUBLIC and anon execute. | none found | `20260323000005_get_member_tier_prefers_db.sql:3` |
| `get_monthly_invite_status` | Caller monthly invite allowance | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no |  | none found | `20260323000001_membership_invites_and_moderation.sql:192` |
| `get_my_project_request` | Caller view of own introduction request | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no |  | none found | `20260710000005_project_engagement.sql:96` |
| `get_news_feed` | Personalised briefing ranking | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | entity_follow_api.test.sql (CI) | `20260718000001_reconcile_intelligence_release_schema.sql:151` |
| `get_pending_for_enrichment` | Pipeline: articles awaiting classification | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | enrich_priority_queue.test.sql (CI) | `20260717000001_enrich_priority_queue.sql:65` |
| `get_project_requests` | Project owner view of introduction requests | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no |  | none found | `20260710000005_project_engagement.sql:78` |
| `get_pulse_edition` | Reads one hand-written Pulse edition | PUBLIC=false anon=false auth=true | none in body | active member | public | no | As get_pulse_feed. | none found | `20260428093500_restore_pulse_review_access.sql:43` |
| `get_pulse_feed` | Lists Pulse editions | PUBLIC=false anon=false auth=true | none in body | active member | public | no | No auth.uid() reference but checks is_active_member(). | none found | `20260428093500_restore_pulse_review_access.sql:9` |
| `get_saved_articles` | Caller saved articles | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | none found | `20260707000001_intelligence_feed.sql:206` |
| `is_active_member` | Helper: caller has an active member row | PUBLIC=true anon=true auth=true | auth.uid() | active member | public | no | PUBLIC and anon execute, returns false for anon. Foundation of most policies. | none found | `20260321000003_authority_hardening_v2.sql:21` |
| `is_admin` | Helper: caller has an admin_roles row | PUBLIC=true anon=true auth=true | auth.uid() | admin | public | no | Ignores members.status, so a suspended administrator still passes (HO-07). PUBLIC and anon execute, returns false for anon. | supabase/verification/p0 (manual, not in CI) | `20260321000003_authority_hardening_v2.sql:26` |
| `is_pending_member` | Helper: caller has a pending member row | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no |  | onboarding_feed_interests.test.sql, release_schema_reconciliation.test.sql (CI) | `20260718000001_reconcile_intelligence_release_schema.sql:49` |
| `map_countries` | Aligned map country aggregates | PUBLIC=false anon=false auth=true | none in body | gold+ via assert_aligned_map_access | public, extensions | no | As map_projects (HO-01). | supabase/verification/p0 (manual, not in CI) | `20260921000001_p0_invitation_containment.sql:434` |
| `map_projects` | Aligned map project points in a bounding box | PUBLIC=false anon=false auth=true | none in body | gold+ via assert_aligned_map_access | public, extensions | no | Gold gate enforced here, but map_cache_projects is readable by any authenticated caller directly (HO-01). | supabase/verification/p0 (manual, not in CI) | `20260921000001_p0_invitation_containment.sql:493` |
| `map_states` | Aligned map Australian state aggregates | PUBLIC=false anon=false auth=true | none in body | gold+ via assert_aligned_map_access | public, extensions | no | As map_projects (HO-01). | supabase/verification/p0 (manual, not in CI) | `20260921000001_p0_invitation_containment.sql:459` |
| `notify_admins_of_issue` | Trigger: pg_net call to notify-admins on issue report | PUBLIC=true anon=true auth=true | none in body | none detected | public | no | Trigger function with PUBLIC execute; direct call is harmless only if it requires trigger context. Reads Vault secret. | none found | `20260710000006_issue_reports.sql:97` |
| `notify_project_engagement` | Trigger: pg_net call to project-engagement on introduction events | PUBLIC=true anon=true auth=true | none in body | none detected | public | no | As notify_admins_of_issue. | none found | `20260710000005_project_engagement.sql:119` |
| `onboarding_admin_aggregates` | Admin cohort aggregates from onboarding | PUBLIC=false anon=false auth=true | auth.uid() | admin | public | no |  | none found | `20260428000001_onboarding_security_foundation.sql:431` |
| `prevent_privileged_member_field_updates` | Trigger: blocks self edits to tier, status and consent fields | PUBLIC=true anon=true auth=true | none in body | admin | public | no | Trigger function with PUBLIC execute. Bypass for service_role and is_admin(); a suspended admin retains the bypass (HO-07). | none found | `20260428000001_onboarding_security_foundation.sql:404` |
| `record_news_events` | Records feed impressions, opens, dwells, hides | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | none found | `20260707000001_intelligence_feed.sql:292` |
| `redeem_invitation_code` | Creates the member row from an invitation after sign in | PUBLIC=false anon=false auth=true | auth.uid() | admin | public | no | Bound to auth.uid() since containment. No throttle of its own: a second oracle for six character codes (HO-04). Recipient email binding compares caller supplied p_email, not the auth email (HO-05). Writes admin_roles and auth.users metadata. | supabase/verification/p0 (manual, not in CI) | `20260921000001_p0_invitation_containment.sql:199` |
| `refresh_map_cache` | Rebuilds map_cache_* tables | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | none found | `20260505000001_safe_map_cache_refresh.sql:7` |
| `release_news_ai_budget_reservation` | Pipeline budget release | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | enrich_priority_queue.test.sql (CI) | `20260717000001_enrich_priority_queue.sql:292` |
| `release_news_pipeline_lease` | Pipeline lease release | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | enrich_priority_queue.test.sql (CI) | `20260717000001_enrich_priority_queue.sql:135` |
| `renew_news_pipeline_lease` | Pipeline lease renewal | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | enrich_priority_queue.test.sql (CI) | `20260718000001_reconcile_intelligence_release_schema.sql:11` |
| `report_issue` | Member files an in-app issue report | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | none found | `20260710000006_issue_reports.sql:44` |
| `request_account_deletion` | Member requests account deletion (flag only) | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no | Sets a flag only; nothing deletes (PR5-09). | none found | `20260425000001_auth_review_and_account_deletion.sql:5` |
| `request_project_contact` | Member requests an introduction to a project owner | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | none found | `20260710000005_project_engagement.sql:26` |
| `reserve_news_ai_budget` | Pipeline budget reservation | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | enrich_priority_queue.test.sql (CI) | `20260717000001_enrich_priority_queue.sql:182` |
| `respond_project_contact` | Project owner approves or declines an introduction | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no |  | none found | `20260710000005_project_engagement.sql:52` |
| `review_aligned_tile` | Admin moderates an Aligned tile | PUBLIC=false anon=false auth=true | auth.uid() | admin | public | no |  | none found | `20260323000001_membership_invites_and_moderation.sql:908` |
| `rsvp_to_event` | Member RSVPs to an event with capacity and tier checks | PUBLIC=false anon=false auth=true | auth.uid() | tier logic | public | no | Takes optional p_member_id; verify it is asserted against auth.uid(). Capacity race under concurrency untested. | none found | `20260710000002_gold_tier_functions.sql:24` |
| `set_entity_follow` | Member follows or unfollows a tracked entity | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | entity_follow_api.test.sql (CI) | `20260717000004_entity_follow_api.sql:22` |
| `set_feed_interests` | Member declares feed interests | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no |  | onboarding_feed_interests.test.sql (CI) | `20260718000001_reconcile_intelligence_release_schema.sql:82` |
| `set_issue_status` | Admin triages an issue report | PUBLIC=false anon=false auth=true | auth.uid() | admin | public | no |  | none found | `20260710000006_issue_reports.sql:74` |
| `settle_news_ai_budget` | Pipeline budget settlement | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | enrich_priority_queue.test.sql (CI) | `20260717000001_enrich_priority_queue.sql:241` |
| `submit_member_onboarding` | Writes onboarding answers, archetype and consent version | PUBLIC=false anon=false auth=true | auth.uid() | none detected | public | no |  | none found | `20260428000001_onboarding_security_foundation.sql:180` |
| `toggle_saved_article` | Member saves or unsaves an article | PUBLIC=false anon=false auth=true | auth.uid() | active member | public | no |  | none found | `20260707000001_intelligence_feed.sql:350` |
| `try_acquire_news_pipeline_lease` | Pipeline lease acquisition | PUBLIC=false anon=false auth=false | none in body | none detected | public | no |  | enrich_priority_queue.test.sql (CI) | `20260717000001_enrich_priority_queue.sql:93` |
| `validate_invitation_code` | Anonymous invitation check, throttled since 20260922000002 | PUBLIC=false anon=true auth=true | auth.uid() | none detected | public, extensions | no | Anon by design. Throttle keyed on auth.uid() or spoofable x-forwarded-for; global ceiling 120 per minute is also a global denial of service lever (HO-06). Runtime rejection not yet proven against production. | supabase/verification/p0 (manual, not in CI) | `20260922000002_short_codes_and_validation_throttle.sql:103` |
| `verify_barcode` | Admin check-in scan of a member pass or ticket | PUBLIC=false anon=false auth=true | auth.uid() | admin | public, extensions | no | Admin only; replay and revocation behaviour needs device test. | none found | `20260707000002_event_ticketing.sql:11` |

## What to do with this inventory

Convert each row into at least one pgTAP assertion under `supabase/tests/database/` that runs in CI:
a grant assertion (`has_function_privilege` for anon, authenticated and PUBLIC) and a behavioural
assertion run as a real `authenticated` JWT for an allowed and a refused actor. Record results in
`07_AUTHORIZATION_MATRIX_STARTER.csv`. Never use the service role as evidence that a policy works.
