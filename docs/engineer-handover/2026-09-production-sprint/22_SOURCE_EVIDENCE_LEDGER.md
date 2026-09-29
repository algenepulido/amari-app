# Source evidence ledger

Every material claim in this pack, with where to check it. Paths are relative to the repository
root at commit `3ce4c4c` unless stated. Migration files are named by their numeric prefix; the full
name is in `supabase/migrations/`. Line numbers point at or within one line of the statement start.

## Evidence labels used in the pack

| Label | Meaning |
|---|---|
| OBSERVED | Read directly from source, configuration or a command run on 29 Sep 2026 |
| DOCUMENTED | Stated in a repository document or the owner's records; not re-verified |
| AUTOMATED TEST ONLY | Covered by a test that ran; no runtime or device evidence |
| REQUIRES DEVICE TEST | Only a physical device can settle it |
| REQUIRES PRODUCTION VERIFICATION | Needs a read-only check against production |
| UNVERIFIED | Not checked |
| KNOWN FAILURE / LIKELY FAILURE | Source reading predicts failure; LIKELY until reproduced |
| LIKELY STALE | Document probably outdated |
| EXTERNAL VERIFICATION REQUIRED | Only a dashboard or console can answer |

## Ledger

| Claim | File | Line or range | Function or component | Migration | Test | Commit | External source required? |
|---|---|---|---|---|---|---|---|
| Pack generated against the release line head | | | | | | `3ce4c4c` | No |
| All build profiles target one Supabase project | `eas.json` | 13, 31, 50 | | | | | Confirm no other project exists |
| Repository private | | | | | | | `gh repo view` on 29 Sep: PRIVATE |
| Expo SDK, RN, router versions | `package.json` | dependencies | | | | | No |
| No Sentry or PostHog SDK | `package.json`; `lib/sentry.ts` | 1-30 | `initSentry` | | | | Whether accounts exist |
| DSN variable not client-inlined | `lib/sentry.ts` | 22-23 | `initSentry` | | | | No |
| Session in SecureStore, auto refresh | `lib/supabase.ts` | 9-39 | `ExpoSecureStoreAdapter` | | | | No |
| Tier and admin from JWT claims in client | `providers/AuthProvider.tsx` | 41-47 | `extractTierFromSession` | | | | No |
| Redemption after sign-in, failure path | `providers/AuthProvider.tsx` | 177-243 | `redeemPendingCode` | | | | Device test |
| Guard signs out members without a row | `app/_layout.tsx` | 65-118 | `AuthGuard` | | | | Device test |
| Deep-link handler for auth callback | `app/_layout.tsx`; `lib/authCallback.ts`; `app/(auth)/auth-callback.tsx` | 429-445; 20-66; 12-30 | `completeAuthFromUrl` | | | | Device test |
| Google iOS falls back without iOS client ID | `lib/googleAuth.ts` | 30-33, 43-68 | `configureGoogleSignIn`, `signInWithGoogleOAuthFallback` | | | | EAS env |
| Apple nonce flow | `lib/appleAuth.ts` | 11-53 | `signInWithApple` | | | | Apple and Supabase config |
| Email sign-up creates users | `app/(auth)/register.tsx` | 96-115 | `handleEmailAuth` | | | | Auth sign-up setting |
| Reviewer password path visible | `app/(auth)/invite.tsx` | 154-178, 427 | `handlePasswordSignIn` | | | | Auth password setting |
| Rate-limit copy says an hour | `app/(auth)/invite.tsx` | 61 | `handleValidate` | | | | No |
| Push registration and tap routing | `lib/push.ts` | 22-76 | `registerToken`, `usePushSetup` | | | | Device test |
| Aligned gate is gold in client | `lib/theme.ts`; `components/v2/CustomTabBar.tsx` | 172-197; 33-56 | `TAB_VISIBILITY` | | | | No |
| Aligned copy says Platinum | `app/(tabs)/aligned/_layout.tsx` | 26 | | | | | No |
| App reads `map_cache_projects` directly | `app/(tabs)/aligned/index.tsx`; `app/(tabs)/profile.tsx` | 393-396; 247 | | | | | No |
| Connections card reads other members | `app/(tabs)/aligned/index.tsx` | 441-470 | | | | | Device test |
| List-screen align is a TODO | `components/aligned/AlignedListScreen.tsx` | 195-205 | `handleAlign` | | | | No |
| Uploads to undefined `public` bucket | `app/admin/events.tsx`; `hooks/useCreateProject.ts` | 98-115; 84-104 | `uploadImage` | | | | Bucket existence |
| Media schema only | `components/pulse/ArticleRow.tsx` | 31-78 | `ArticleRow` | `20260707000005` 12-25 | | | No |
| 48 tables, all RLS; 57 policies; 65 definer; 13 invoker; 11 triggers | `supabase/migrations/` (58 files) | parser | | all | | | Live catalogue for current state |
| Live catalogue 22 Sep: 68 definer incl. 3 PostGIS; grants; 57 policies | `docs/evidence/after-20260922T011536Z-statement-one.csv` | sections 2, 4 | | | | | Re-capture recommended |
| Containment applied 22 Sep, hashes | `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`; `docs/evidence/DEPLOYMENT_RECORD.md` | whole | | `20260921000001` | `supabase/verification/p0/` | | No |
| Short codes and throttle | | | `validate_invitation_code`, `generate_share_invite_code` | `20260922000002` 46-165 | P0 suite (manual) | | Runtime rejection |
| Redemption bound to `auth.uid()`; email binding uses `p_email` | | | `redeem_invitation_code` | `20260921000001` 199-340, 222-228, 255-262 | P0 suite (manual) | | No |
| No throttle in redemption | | | `redeem_invitation_code` | `20260921000001` 199-340 | none | | Live body comparison |
| Map functions gated at gold | | | `assert_aligned_map_access`, `map_*` | `20260921000001` 378-520 | P0 suite (manual) | | No |
| Map cache tables readable by all authenticated | | | | `20260326000001` 128-156 | none | | Live policy and grants |
| Projects policies | | | | `20260326000001` 73-82 | none | | Live policy |
| `is_admin()` ignores status; suspension does not touch `admin_roles` | | | `is_admin`, `admin_set_member_status` | `20260321000003` 26-29; `20260504000002` 7 | none | | Reproduce |
| Access-token hook claims | | | `custom_access_token_hook` | `20260301000004` 6-30 | none | | Hook enabled in dashboard |
| `get_member_tier` JWT fallback | | | `get_member_tier` | `20260323000005` 3-30 | none | | No |
| RSVP capacity branch uses `FOUND` after `count(*)` | | | `rsvp_to_event` | `20260710000002` 24-49 | none | | Reproduce |
| Cancel does not promote waitlist | | | `cancel_event_rsvp` | `20260707000002` 77-91 | none | | No |
| Feed ranking shape and indexes | | | `get_news_feed` | `20260718000001` 151-250; `20260707000001` 49-58, 78-81 | `entity_follow_api.test.sql` | | No |
| Four cron jobs in version control | | | | `20260301000005` 6-27 | none | | `cron.job` |
| Runbook-only schedules | `supabase/functions/NEWS-PIPELINE.md` | 45-95 | | | | | `cron.job` |
| pg_net triggers read Vault secret | | | `notify_project_engagement`, `notify_admins_of_issue` | `20260710000005` 119-139; `20260710000006` 97-110 | none | | Vault secret present |
| Edge Function auth | `supabase/functions/*/index.ts` | e.g. `ingest-news` 70-88 | `isAuthorized` | | Deno (core logic) | | Deploy flags |
| Classifier model pinned | `supabase/functions/enrich-news/index.ts`; `core_test.ts` | 25-45; 80-81 | | | Deno | | Provider secrets |
| Push chunks sequential, no receipts | `supabase/functions/send-briefing-push/index.ts` | 86-127 | | | none | | No |
| Storage bucket and policies | | | | `20260321000003` 261, 273-275 | none | | Bucket limits |
| Onboarding writes consent version and interests | `app/(onboarding)/index.tsx` | 35, 667-715 | | `20260428000001` 180 | `onboarding_feed_interests.test.sql` | | Production counts |
| Security verifier scope | `scripts/verify-security.mjs` | 5 | | | | | No |
| Keystore workflow exposure | `.github/workflows/setup-keystore.yml` | 1-40 | | | | | Play App Signing |
| Android builds via Actions only | `.github/workflows/eas-build.yml`; `docs/RELEASE-WORKFLOW.md` | whole | | | | | No |
| OTA blocked | `docs/eas-update.md` | 3-9 | | | | | Expo plan |
| 1.2.5 build numbers and hashes | `docs/releases/1.2.5-artifacts.md` | 12-40 | | | | | Store consoles |
| Stale docs: 48-character codes | `README.md`; `CLAUDE.md`; `AGENTS.md` | 12 each | | | | | No |
| Gates at `3ce4c4c` | local run 29 Sep 2026 | | | | Jest 77 of 77; Deno 15 of 15; lint 0 errors; tsc clean | `3ce4c4c` | No |
| CI green at `3ce4c4c` including pgTAP | GitHub Actions run 35967017046 | | | | CI | `3ce4c4c` | No |
| Production counts (members, admins, invitations) | `docs/evidence/DEPLOYMENT_RECORD.md` | Before and after table | | | | | Point in time, 22 Sep |
| Store and platform state | 5 Sep readiness report (outside repo); owner's Play Console notes 22 Sep | | | | | | Yes |
