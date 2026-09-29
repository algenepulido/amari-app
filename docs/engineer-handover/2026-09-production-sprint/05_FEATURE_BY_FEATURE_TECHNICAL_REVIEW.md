# Feature-by-feature technical review

Commit `3ce4c4c`. This is the feature review Algene asked for. No earlier stand-alone feature review
was found; the closest predecessor is the feature inventory inside the 5 September readiness report,
reconciled here and in `06`.

**How to read the status column.** A component existing is not readiness. Status uses: IMPLEMENTED
IN SOURCE (code path exists end to end, not proven at runtime), PARTIAL (a link in the chain is
missing or suspect), LIKELY FAILURE (source reading predicts a defect), NOT BUILT, HIDDEN.
**Test coverage** says what automated test exists. **Device** says whether any recorded physical
device result exists at this commit; for every feature below the answer is NONE RECORDED, and
1.2.5 was shipped without a hardware acceptance pass according to the 5 September report. Priority
uses the sprint scale P0 to P3.

Common abbreviations: `(auth)`, `(tabs)` and `(onboarding)` are route groups under `app/`.
Migration files are cited by their numeric prefix.

## Summary table

| Feature | Status | Priority |
|---|---|---|
| Application launch | IMPLEMENTED IN SOURCE | P1 |
| Invitation validation | IMPLEMENTED IN SOURCE, throttle unproven | P0 |
| Account creation and redemption | IMPLEMENTED IN SOURCE, security gaps HO-04, HO-05 | P0 |
| Apple sign-in | IMPLEMENTED IN SOURCE | P0 |
| Google sign-in | PARTIAL on iOS (browser fallback) | P0 |
| Email OTP and magic link | IMPLEMENTED IN SOURCE | P0 |
| Reviewer password sign-in | IMPLEMENTED IN SOURCE | P1 |
| Onboarding | IMPLEMENTED IN SOURCE | P0 |
| Home (Pulse digest) | IMPLEMENTED IN SOURCE | P1 |
| Briefing and news feed | IMPLEMENTED IN SOURCE | P1 |
| Interests | IMPLEMENTED IN SOURCE | P1 |
| Save and hide | IMPLEMENTED IN SOURCE | P2 |
| Entity follow | IMPLEMENTED IN SOURCE | P2 |
| Pulse editions | IMPLEMENTED IN SOURCE | P2 |
| Events list and detail | IMPLEMENTED IN SOURCE | P1 |
| RSVP and cancel | LIKELY FAILURE for capacity-limited events (HO-25) | P0 |
| Event capacity and waitlist | LIKELY FAILURE (HO-25) | P0 |
| Ticket and QR | IMPLEMENTED IN SOURCE | P1 |
| Admin check-in | IMPLEMENTED IN SOURCE | P1 |
| Aligned matching | IMPLEMENTED IN SOURCE | P1 |
| Tier gating | Client and database disagree in places (HO-01, HO-02) | P0 |
| Interest, skip, reveal | PARTIAL (list-screen reveal is a TODO) | P1 |
| Reporting and safety in Aligned | NOT BUILT on the client | P1 |
| Projects, create | PARTIAL (cover upload bucket, HO-09; self-approval, HO-03) | P1 |
| Project map | IMPLEMENTED IN SOURCE | P1 |
| Project shelves and detail | IMPLEMENTED IN SOURCE | P1 |
| Project media (cover images) | LIKELY FAILURE (HO-09) | P1 |
| Project journals and updates | IMPLEMENTED IN SOURCE | P2 |
| Introductions, request, approve, decline, reveal | IMPLEMENTED IN SOURCE | P1 |
| Recent connections card | LIKELY FAILURE (RLS hides other members' names) | P2 |
| In-app notifications | PARTIAL | P2 |
| Profile and account | IMPLEMENTED IN SOURCE | P1 |
| Notification preferences | IMPLEMENTED IN SOURCE | P2 |
| Issue reporting | IMPLEMENTED IN SOURCE | P2 |
| Account deletion | PARTIAL (request only) | P1 |
| Logout and re-login | IMPLEMENTED IN SOURCE | P0 |
| Push notifications | PARTIAL | P1 |
| Deep links | PARTIAL | P0 |
| Media, audio | NOT BUILT | P1 core |
| Media, video | NOT BUILT | P1 core |
| Admin console | IMPLEMENTED IN SOURCE | P1 |
| Corridor | HIDDEN | P3 |
| Profile pictures | NOT BUILT | Stretch |

## Entry, identity and onboarding

### Application launch
- **Status:** IMPLEMENTED IN SOURCE.
- **Journey:** cold start, font load, 3-second animated splash, session restore from SecureStore, `AuthGuard` routing.
- **Entry point:** `app/_layout.tsx:381-497`.
- **Files:** `app/_layout.tsx`, `lib/supabase.ts`, `providers/AuthProvider.tsx:49-94`, `components/ErrorBoundary.tsx`.
- **Tables and RPCs:** `members` (own row via `queries/members.ts`).
- **Edge Functions, buckets:** none.
- **Permission dependencies:** `members_self_read`.
- **Tests:** none.
- **Known issues:** the splash always costs about 3 seconds (`app/_layout.tsx:130-138`); `initSentry()` is a no-op; `SecureStore` session size on Android is untested (PR5-20).
- **Device:** NONE RECORDED. Cold-start time is a sprint measurement.
- **Priority:** P1.

### Invitation validation
- **Status:** IMPLEMENTED IN SOURCE. Throttle added 22 Sep, rejection unproven at runtime.
- **Journey:** onboarding carousel or `/(auth)/invite`, enter code, `validate_invitation_code`, then `/(auth)/register?code=...`.
- **Entry point:** `components/v2/Onboarding.tsx:318`, `app/(auth)/invite.tsx:44-89`.
- **RPC:** `validate_invitation_code` (`20260922000002:103`), anon and authenticated.
- **Tables:** `invitation_codes` (hash lookup), `rate_limits`.
- **Tests:** `supabase/verification/p0/` (manual, not CI).
- **Known issues:** HO-06 (spoofable per-caller key, global ceiling is a denial-of-service lever); client copy says "wait an hour" while the window is 10 minutes (`app/(auth)/invite.tsx:61`).
- **Device:** NONE RECORDED.
- **Priority:** P0.

### Account creation and invitation redemption
- **Status:** IMPLEMENTED IN SOURCE with security gaps.
- **Journey:** register screen stores `pending_invitation_code` JSON in SecureStore, signs in, then `AuthProvider` calls `redeem_invitation_code` with the auth user id and the session email, refreshes the session, syncs profile fields.
- **Files:** `app/(auth)/register.tsx:46-60`, `providers/AuthProvider.tsx:177-243`.
- **RPC:** `redeem_invitation_code` (`20260921000001:199`).
- **Tables:** `invitation_codes`, `members`, `admin_roles`, `auth.users.raw_app_meta_data`.
- **Permission dependencies:** authenticated only since containment; binds to `auth.uid()`.
- **Tests:** P0 suite (manual).
- **Known issues:** HO-04 no throttle on redemption; HO-05 email binding uses caller-supplied `p_email`; if the RPC errors (for example a network drop), the pending code is kept but setup is marked complete, so `AuthGuard` finds no member row, shows "Membership not activated" and signs the person out (`providers/AuthProvider.tsx:208-238`, `app/_layout.tsx:87-98`). Recovery then depends on the code still being in SecureStore; REQUIRES DEVICE TEST.
- **Device:** NONE RECORDED.
- **Priority:** P0.

### Apple sign-in
- **Status:** IMPLEMENTED IN SOURCE. iOS only.
- **Files:** `lib/appleAuth.ts:11-53`; nonce is hashed and passed; name and email written to `user_metadata` after sign-in.
- **Known issues:** Hide My Email yields a `privaterelay.appleid.com` address, which the redemption function exempts from recipient binding (HO-05). Relay addresses are scoped to the Apple team, so any developer-team change would orphan those accounts (EXTERNAL).
- **Tests:** none. **Device:** NONE RECORDED. **Priority:** P0.

### Google sign-in
- **Status:** PARTIAL on iOS.
- **Files:** `lib/googleAuth.ts`. Native flow on Android; on iOS the native flow only configures when `EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID` is set (`lib/googleAuth.ts:30-33`), which `eas.json` does not set. Otherwise `signInWithOAuth` opens a browser session back to `https://www.amarigroupau.com/auth-callback`, which must then hand off to `amari://auth-callback`.
- **Known issues:** the fallback depends on the website callback page and the custom scheme; see `09`. After a failed native sign-in the code silently falls back to the browser (`lib/googleAuth.ts:88-97`).
- **Tests:** none. **Device:** NONE RECORDED. **Priority:** P0.

### Email OTP and magic link
- **Status:** IMPLEMENTED IN SOURCE.
- **Files:** `app/(auth)/register.tsx:77-150` (`shouldCreateUser: true`), `app/(auth)/invite.tsx:91-154` for existing members (`shouldCreateUser: false`), `lib/authCallback.ts`.
- **Known issues:** magic links go to the website callback and back into the app via deep link; opening on another device leaves the pending code on the first device. Email deliverability and Auth rate limits are EXTERNAL.
- **Tests:** none. **Device:** NONE RECORDED. **Priority:** P0.

### Reviewer password sign-in
- **Status:** IMPLEMENTED IN SOURCE. The "Reviewer password access" toggle is rendered to everyone on the invitation screen (`app/(auth)/invite.tsx:427`) and calls `signInWithPassword`.
- **Known issues:** exposes a password path in production UI; whether email and password sign-in is enabled in the Auth dashboard is EXTERNAL. Useful for test identities (see `12`).
- **Priority:** P1.

### Onboarding
- **Status:** IMPLEMENTED IN SOURCE.
- **Journey:** five steps including sector and region interests, archetype scoring, consent; writes through `submit_member_onboarding` and `set_feed_interests`.
- **Files:** `app/(onboarding)/index.tsx` (1,094 lines; consent version constant at line 35; interests at 667-715), `queries/onboarding.ts`.
- **RPCs:** `submit_member_onboarding` (`20260428000001:180`), `set_feed_interests`.
- **Tables:** `members.onboarded_at`, `consent_given_at`, `consent_version`, `member_onboarding_responses`, `member_onboarding_snapshots`, `member_onboarding_evidence_ledger`, `member_feed_interests`.
- **Tests:** `__tests__/onboardingFeedInterests.test.ts` (asserts source text), `supabase/tests/database/onboarding_feed_interests.test.sql` (CI).
- **Known issues:** the July defect "onboarding never sets interests" is changed in source (APPARENTLY CHANGED, REVERIFY). Existing members without consent need a product decision (PR5-08).
- **Device:** NONE RECORDED. **Priority:** P0.

## Content

### Home (Pulse digest)
- **Status:** IMPLEMENTED IN SOURCE. **Entry:** `app/(tabs)/index.tsx`. **Components:** `components/pulse/*` (hero carousel, bridge tiles, briefing preview, quick actions). **RPCs:** `get_pulse_feed`, `get_news_feed`. **Known issues:** the fabricated "Matched to your profile" footer reported in July is gone from source (`getPulseMatchFooter` no longer referenced; `__tests__/pulseMatchFooterRemoval.test.ts`). **Priority:** P1.

### Briefing and news feed
- **Status:** IMPLEMENTED IN SOURCE.
- **Entry:** `app/briefing.tsx`. **Queries:** `queries/news.ts:13` `get_news_feed(p_limit, p_offset)`.
- **Tables:** `news_articles`, `news_sources`, `member_feed_interests`, `member_entity_follows`, `news_events`, `saved_articles`.
- **Edge Functions:** `ingest-news`, `enrich-news` produce the content.
- **Permission:** `get_news_feed` returns nothing unless `is_active_member()`.
- **Tests:** `entity_follow_api.test.sql` (CI) exercises ranking with follows; Deno tests cover ingest and enrich core logic.
- **Known issues:** OFFSET pagination and per-request scoring (PR5-06); no editorial gate beyond the classifier threshold.
- **Priority:** P1.

### Interests
- **Status:** IMPLEMENTED IN SOURCE. `components/pulse/InterestSheet.tsx`, `queries/news.ts:45-60`, `set_feed_interests`. **Priority:** P1.

### Save and hide
- **Status:** IMPLEMENTED IN SOURCE. `toggle_saved_article`, `get_saved_articles`, hides via `record_news_events` with `event_type = 'hide'`. **Known issues:** the hide anti-join index shape (PR5-06); `news_events` has no retention. **Priority:** P2.

### Entity follow
- **Status:** IMPLEMENTED IN SOURCE. `components/pulse/EntityFollowSheet.tsx` imported by `app/briefing.tsx:11` and `components/pulse/BriefingPreview.tsx:12`; `set_entity_follow`. The July note "no client UI" is changed (APPARENTLY CHANGED, REVERIFY). Production had zero follows at 5 Sep. **Priority:** P2.

### Pulse editions
- **Status:** IMPLEMENTED IN SOURCE. Admin authoring at `app/admin/pulse.tsx`; members read via `get_pulse_feed` and `get_pulse_edition`. Newest edition was 1 July at 5 Sep (content, not engineering). **Priority:** P2.

## Events

### Events list and detail
- **Status:** IMPLEMENTED IN SOURCE. `app/(tabs)/events.tsx`, `components/EventDetailSheet.tsx`, `components/events/*`, `queries/events.ts:23-74`. **Table:** `events` (`events_select` requires active member). **Priority:** P1.

### RSVP, cancel and capacity
- **Status:** LIKELY FAILURE for capacity-limited events.
- **RPCs:** `rsvp_to_event` (`20260710000002:24-49`), `cancel_event_rsvp`.
- **Defect HO-25:** after the existing-RSVP lookup, the capacity branch runs `select count(*) into v_current_count`, which always sets PL/pgSQL `FOUND` to true. The following `if found then update ... where id = v_existing.id` then updates no row for a first-time RSVP, and the function still returns `success: true`. Events without a capacity take the `else` branch, leave `FOUND` false and insert correctly. Reproduce on local Supabase before any claim is made.
- **Other:** the event row is locked `for update`, which serialises concurrent RSVPs; `cancel_event_rsvp` (`20260707000002:77-91`) sets the row to cancelled and promotes nobody from the waitlist (OBSERVED); whether manual promotion is intended is a product question.
- **Tests:** none. **Priority:** P0 because it silently loses RSVPs.

### Ticket and QR
- **Status:** IMPLEMENTED IN SOURCE. `components/events/TicketModal.tsx`, `lib/barcode.ts`, `hooks/useBarcode.ts`, `generate_barcode_token`, `barcode_seeds`, `barcode_revocations`. **Tests:** `__tests__/lib/events.test.ts` covers helpers only. **Priority:** P1.

### Admin check-in
- **Status:** IMPLEMENTED IN SOURCE. `app/admin/checkin.tsx` (camera scanner), `verify_barcode`, `get_event_checkin_stats`. **Known issues:** camera permission denial path and replay of a revoked pass need device tests. **Priority:** P1.

## Aligned and projects

### Aligned matching
- **Status:** IMPLEMENTED IN SOURCE. `app/(tabs)/aligned/index.tsx` (1,745 lines), `queries/aligned.ts:59` `aligned_decide`; weekly `generate_weekly_matches` by cron; `aligned_matches`, `aligned_skips`, `aligned_interests`, `aligned_history`. **Priority:** P1.

### Tier gating
- **Status:** client and database disagree in places.
- **Client:** `components/v2/CustomTabBar.tsx:33-56` hides Aligned below gold using the JWT claim; `lib/theme.ts:191-197`.
- **Database:** map RPCs require gold via `assert_aligned_map_access` (`20260921000001:378`); `map_cache_*` tables and approved `projects` do not (HO-01, HO-02). The app itself reads `map_cache_projects` directly (`app/(tabs)/aligned/index.tsx:393-396`, `app/(tabs)/profile.tsx:247`), so tightening those policies must be coordinated with the client.
- **Copy:** `app/(tabs)/aligned/_layout.tsx` tells members Aligned is available from Platinum; the enforced rule is gold. Product decision.
- **Stale code:** `components/TierGate.tsx:6` has a four-tier map without gold; nothing imports it.
- **Priority:** P0.

### Interest, skip, reveal
- **Status:** PARTIAL. Match decisions go through `aligned_decide`. In the list screen, skip is local state only and "align" is a TODO (`components/aligned/AlignedListScreen.tsx:195-205`). Contact reveal after mutual interest is `get_aligned_tile_contact_details`. **Priority:** P1.

### Reporting and safety in Aligned
- **Status:** NOT BUILT on the client. `aligned_reports` exists with RLS and no policy; no client code writes to it and no RPC for filing a report was found. Report and block are expected by store reviewers for user-generated contact features; confirm the product position. **Priority:** P1.

### Projects, create
- **Status:** PARTIAL. `app/(tabs)/aligned/create.tsx`, `hooks/useCreateProject.ts` inserts into `projects` with `status: 'pending'` (line 122). Admin review at `app/admin/aligned.tsx` via `admin_set_project_status`.
- **Known issues:** HO-03 the creator policy appears to let an owner change their own status to approved; HO-09 the cover upload goes to bucket `public`, and on upload error the code continues without an image and without telling the person (`hooks/useCreateProject.ts:96-104`).
- **Priority:** P1.

### Project map
- **Status:** IMPLEMENTED IN SOURCE. `components/aligned/ProjectMap.tsx`, `hooks/useMapData.ts`, `hooks/useMapViewport.ts`, `lib/mapbox.ts`; `map_projects`, `map_states`, `map_countries`; cache rebuilt by `refresh_map_cache` (service role, `refresh-map-data` function). Mapbox attribution is guarded by `scripts/verify-release.mjs` per the 5 Sep report. **Priority:** P1.

### Project shelves and detail
- **Status:** IMPLEMENTED IN SOURCE. `components/aligned/ProjectShelves.tsx`, `ProjectPage.tsx`, `queries/projects.ts:22-62`. **Priority:** P1.

### Project media (cover images)
- **Status:** LIKELY FAILURE (HO-09). No migration creates a `public` bucket. The 5 Sep report counted zero storage objects in production, which is consistent with uploads never succeeding. Whether the bucket exists in the dashboard is EXTERNAL. **Priority:** P1.

### Project journals and updates
- **Status:** IMPLEMENTED IN SOURCE. `project_updates` with creator-only insert on approved projects (`20260707000004`). Production had zero updates at 5 Sep. **Priority:** P2.

### Introductions
- **Status:** IMPLEMENTED IN SOURCE. `request_project_contact` (12 to 600 character note), `respond_project_contact`, `get_project_requests`, `get_my_project_request`; `project_contact_requests` has no direct policies; pushes via `tr_pcr_notify` and `project-engagement`. Contact is revealed only after approval. **Tests:** none. Production had zero requests at 5 Sep. **Priority:** P1.

### Recent connections card
- **Status:** LIKELY FAILURE. `app/(tabs)/aligned/index.tsx:441-470` reads the other members' `full_name` and `city` from `members`, but `members_self_read` only returns the caller's own row, so names come back empty for non-admins. REQUIRES DEVICE TEST. **Priority:** P2.

## Account

### In-app notifications
- **Status:** PARTIAL. `notifications` table with own-row policies; used as a Realtime trigger for tier refresh (`providers/AuthProvider.tsx:246-268`). No notification centre screen was found. Whether `notifications` is in the Realtime publication is EXTERNAL. **Priority:** P2.

### Profile and account
- **Status:** IMPLEMENTED IN SOURCE. `app/(tabs)/profile.tsx` (855 lines), `components/v2/ProfileMembershipCard.tsx`, `components/EditFieldModal.tsx`; own `members` row update guarded by `tr_prevent_privileged_member_field_updates`. **Priority:** P1.

### Notification preferences
- **Status:** IMPLEMENTED IN SOURCE. `members.notification_preferences` JSON, honoured by `send-briefing-push` (`prefs.pulse !== false`). **Priority:** P2.

### Issue reporting
- **Status:** IMPLEMENTED IN SOURCE. `components/v2/ReportIssueSheet.tsx`, `report_issue`, trigger `tr_issue_notify` to `notify-admins`, triage at `app/admin/issues.tsx` with `set_issue_status`. **Priority:** P2.

### Account deletion
- **Status:** PARTIAL. `request_account_deletion` sets a flag and a notification (`20260425000001:5`); nothing deletes (PR5-09). App Store guideline 5.1.1(v) expectations are EXTERNAL and a product decision. **Priority:** P1.

### Logout and re-login
- **Status:** IMPLEMENTED IN SOURCE. `supabase.auth.signOut()`; `SIGNED_OUT` clears the query cache (`providers/AuthProvider.tsx:88-90`). The Google native session is signed out before each Google sign-in (`lib/googleAuth.ts:85`). Push token is not cleared from `members` on logout, so a shared device keeps receiving the previous member's pushes until another member registers. REQUIRES DEVICE TEST. **Priority:** P0.

## Platform services

### Push notifications
- **Status:** PARTIAL. Registration after sign-in in the tabs layout (`lib/push.ts:53-62`); tap routing for `briefing`, `project`, `issue` (`lib/push.ts:64-76`). Only a response listener is registered; there is no `getLastNotificationResponseAsync` call, so a tap that cold-starts a killed app may not route (HO-13, REQUIRES DEVICE TEST). Fan-out and dead-token pruning are PR5-07. **Priority:** P1.

### Deep links
- **Status:** PARTIAL. Only `amari://auth-callback` is handled explicitly (`app/_layout.tsx:429-445`, `app/(auth)/auth-callback.tsx`). No universal links or Android App Links are configured (`app.json` has no `associatedDomains` or `intentFilters`). The callback accepts tokens from any URL with that path (HO-12). **Priority:** P0 for the auth return path.

### Media, audio and video
- **Status:** NOT BUILT. See `13`. **Priority:** P1, core deliverable.

### Admin console
- **Status:** IMPLEMENTED IN SOURCE. `app/(tabs)/admin.tsx` plus `app/admin/` screens: `members` (tier and status), `codes` (invitations), `events` (create, with image upload to `public`, HO-09), `checkin`, `aligned` (tile and project review), `pulse` (editions), `issues`. Client gate at `app/admin/_layout.tsx:18-28`; server gates are `is_admin()` checks and admin policies. **Known issues:** HO-07 suspended administrators. **Priority:** P1.

### Corridor
- **Status:** HIDDEN. `app/(tabs)/corridor.tsx` renders waitlist copy; `TAB_VISIBILITY.corridor = 99` hides it; `lib/constants.ts` carries a dead value of 2. **Priority:** P3.

### Profile pictures
- **Status:** NOT BUILT. Stretch only.
