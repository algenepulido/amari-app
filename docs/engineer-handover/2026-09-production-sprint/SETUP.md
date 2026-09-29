# Setup

How to get the project running, which environment to test in, what access exists, and which test accounts to create. Commit `3ce4c4c`.

## Repository and local setup

Every command below was checked against `package.json`, `eas.json`, `.github/workflows/ci.yml` and
`.husky/` at commit `3ce4c4c`. Commands marked OBSERVED were run on 29 September 2026 in a clean
worktree on Windows 11 with Node 24.12.0; the rest are read from configuration and not run.

### Stale guidance you will meet in the repository

Implementation wins over these. Each is also in `SECURITY.md` as a documentation finding.

- `README.md`, `CLAUDE.md` and `AGENTS.md` say new invitation codes are 48 characters. Migration `20260922000002_short_codes_and_validation_throttle.sql:46-78` changed the generator to six Crockford base32 characters, and that migration ran against production according to `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`.
- `CLAUDE.md` and `AGENTS.md:84-89` say to work in `C:\amari-ui-build` on the release branch. That is the owner's machine layout, and that worktree is on a different branch today. For you: clone, check out `release/v2-redesign-signed`, branch from it.
- `supabase/functions/NEWS-PIPELINE.md:34` says to set `OPENAI_MODEL`; the code rejects that override.
- `master` is the GitHub default branch and is 131 commits behind the release line. PR #5 (`release/v2-redesign-signed` into `master`) has been open since March. Do not merge or close it without the owner.

### Layout

| Path | What lives there |
|---|---|
| `app/` | expo-router routes. `(auth)`, `(onboarding)`, `(tabs)`, `admin/`, `briefing.tsx`, root `_layout.tsx` with the auth guard |
| `components/` | `aligned/`, `events/`, `pulse/`, `v2/` (current design system components), `ui/`, `badges/`, plus root-level legacy components such as `TierGate.tsx` (unused) |
| `lib/` | Supabase client, auth helpers (`appleAuth.ts`, `googleAuth.ts`, `authCallback.ts`, `authRedirect.ts`), `push.ts`, `mapbox.ts`, `theme.ts` (current tokens and tier levels), `constants.ts` (legacy tokens), `sentry.ts` and `posthog.ts` shims, `reportError.ts` |
| `providers/` | `AuthProvider.tsx` (session, claims, invitation redemption), `QueryProvider.tsx` |
| `queries/` | TanStack Query hooks per domain: `news`, `events`, `aligned`, `projects`, `members`, `onboarding`, `pulse`, `issues`, `cityPresence` |
| `hooks/` | Feature hooks: project and tile creation with uploads, map viewport, barcode, bookmarks |
| `constants/` | Feed tag vocabulary, explore content, gala nominee copy |
| `supabase/migrations/` | 58 forward-only migrations, `20260301000000` to `20260922000002` |
| `supabase/functions/` | Six Deno Edge Functions and `NEWS-PIPELINE.md` |
| `supabase/tests/database/` | Five pgTAP files, run in CI |
| `supabase/verification/p0/` | Containment pgTAP suite, authorisation matrix SQL and Docker fixtures. Deliberately outside the CI path; run by hand |
| `scripts/` | Release verifier, security verifier, invitation and tester tooling (SQL run by psql), production-update guard |
| `__tests__/` | Jest, pure logic |
| `docs/` | Working memory, release workflow, security records, evidence CSVs |
| `.github/workflows/` | `ci.yml`, `eas-build.yml` (Android), `setup-keystore.yml` (one-off, see HO-18) |
| `certs/certificate.pem` | Public certificate for signed EAS Updates. The private key is gitignored and must never be committed |
| Root `*.html`, `CODEX-*.md`, `generate_americas.py` | Design prototypes and agent briefs. Not part of the app |

### Configuration files

| File | Role |
|---|---|
| `app.json` | Expo config: name, version 1.2.5, scheme `amari`, bundle and package `com.amari.mobile`, plugins, `runtimeVersion` policy `appVersion`, signed updates config |
| `app.config.js` | Wraps `app.json`; fails an EAS build without Mapbox tokens; injects the Google iOS URL scheme when `EXPO_PUBLIC_GOOGLE_IOS_URL_SCHEME` is set |
| `eas.json` | Build profiles and public `EXPO_PUBLIC_*` values; `appVersionSource: remote`; production `autoIncrement` |
| `supabase/config.toml` | Local Supabase: auth redirect list, access-token hook, Apple and Google providers read from env |
| `tsconfig.json` | `strict: true`, `@/*` alias |
| `jest.config.js` | `jest-expo` preset with `testEnvironment: 'node'` |
| `eslint.config.mjs` | ESLint 9 flat config |
| `.husky/pre-commit`, `.husky/pre-push` | `lint-staged`; `npm run verify:release` before every push |

### Required local software

| Tool | Version guidance | Source |
|---|---|---|
| Node | CI uses 20 (`ci.yml`), the Android build uses 22 (`eas-build.yml`). No `engines` field or `.nvmrc`. Gates also passed on 24.12.0 locally. Use 20 or 22. | workflows |
| npm | Lockfile is `package-lock.json`; use `npm ci` | repository |
| EAS CLI | `eas.json` requires `>= 10.0.0`; 18.4.0 worked locally | `eas.json:3` |
| Deno | 2.x | `ci.yml` |
| Supabase CLI | CI pins 2.109.1 | `ci.yml` |
| Docker | Needed for `supabase db start` and the P0 fixtures | `ci.yml`, `supabase/verification/p0/README.md` |
| Xcode and Android Studio | For development builds on simulators and devices | Expo standard |

### Environment variable names

Values are never written here. Public values ship inside the app binary by design.

| Name | Where set | Public? | Purpose |
|---|---|---|---|
| `EXPO_PUBLIC_SUPABASE_URL` | `eas.json` all profiles, local `.env` | Public | Supabase project URL |
| `EXPO_PUBLIC_SUPABASE_ANON_KEY` | `eas.json` all profiles, local `.env` | Public (legacy anon JWT) | Client key |
| `EXPO_PUBLIC_AUTH_REDIRECT_URL` | `eas.json` | Public | OAuth and magic-link return page |
| `EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID` | `eas.json` | Public | Google Sign-In |
| `EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID` | `eas.json` | Public | Google Sign-In, Android |
| `EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID` | Not in `eas.json`; EAS environment unknown | Public | Native Google Sign-In on iOS. Absent means browser fallback |
| `EXPO_PUBLIC_GOOGLE_IOS_URL_SCHEME` | Not in `eas.json` | Public | Reversed client ID scheme for native iOS Google |
| `EXPO_PUBLIC_MAPBOX_TOKEN` | GitHub secret, injected by `eas-build.yml`; EAS env for iOS unknown | Public token | Map rendering |
| `EXPO_PUBLIC_MAPBOX_STYLE_URL` | `.env.example` only | Public | Map style |
| `RNMAPBOX_MAPS_DOWNLOAD_TOKEN` or `MAPBOX_SECRET_TOKEN` | EAS secret, local `.env` | SECRET | Native SDK download at build time |
| `EXPO_PUBLIC_POSTHOG_KEY`, `EXPO_PUBLIC_POSTHOG_HOST` | `.env.example` only | Public | Unused shim |
| `SENTRY_DSN` | `.env.example` only | Public DSN | Unused shim. Note: a name without `EXPO_PUBLIC_` is not inlined into the client bundle (HO-14) |
| `EAS_UPDATE_PRIVATE_KEY_PATH` | Local only | SECRET path | Signed OTA; not in use |
| `EXPO_TOKEN` | GitHub secret | SECRET | EAS in Actions |
| `ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD` | GitHub secrets | SECRET | Android upload key for Play builds |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Edge Function runtime | Service role is SECRET | Edge Functions |
| `NEWS_PIPELINE_SECRET` | Edge Function secret; the same value lives in Vault as `news_pipeline_secret` | SECRET | Shared caller secret for all pipeline and push functions |
| `LLM_PROVIDER`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENAI_BASE_URL` | Edge Function secrets | Keys are SECRET | Classifier |
| `SUPABASE_AUTH_APPLE_CLIENT_ID`, `SUPABASE_AUTH_APPLE_SECRET`, `SUPABASE_AUTH_GOOGLE_CLIENT_ID`, `SUPABASE_AUTH_GOOGLE_SECRET` | Local Supabase only; production values in the Auth dashboard | Secrets are SECRET | Auth providers |

The owner's local `.env` holds the Supabase URL and anon key, both Google client IDs, the Mapbox
public token and the Mapbox download token. It is gitignored. Ask for your own Mapbox download
token rather than a copy of that file.

### Commands

| Purpose | Command | Status |
|---|---|---|
| Install | `npm ci` | OBSERVED, 1,395 packages, 28 s |
| Dev server with dev client | `npm run start:dev` | Not run |
| Android dev | `npm run android:dev` | Not run; requires a development build |
| iOS | `npm run ios` | Not run; requires macOS |
| Lint | `npm run lint` | OBSERVED: 0 errors, 27 warnings |
| Typecheck | `npm run typecheck` | OBSERVED: clean |
| Security verifier | `npm run verify:security` | OBSERVED: pass. Scans `app components hooks lib providers queries` only, not `supabase/` (`scripts/verify-security.mjs:5`) |
| Unit tests | `npm run test:ci` | OBSERVED: 10 suites, 77 tests, all pass |
| Deno tests | `deno test --allow-read --no-config supabase/functions` | OBSERVED: 15 passed |
| pgTAP | `supabase db start` then `supabase test db` | Not run locally; passed in CI run 35967017046 on `3ce4c4c`, 24 Sep 2026 |
| Release verifier | `npm run verify:release` | Runs on every push via husky |
| P0 suite | See `supabase/verification/p0/README.md` | Manual, Docker |
| Mobile flow script | `npm run test:mobile-flows` | Safe: static source checks only, no network calls; also runs inside `verify:release` on every push. Its `--manual` and tester modes print test scripts that embed an already-redeemed production invitation code and a named person's email; do not share that output |
| Production dependency audit | `npm audit --omit=dev` | OBSERVED: 34 advisories, 2 critical, 10 high. Whether any reaches the shipped bundle is UNVERIFIED |

### EAS build profiles

| Profile | Distribution | Supabase target | Channel | Notes |
|---|---|---|---|---|
| `development` | internal, dev client | production project | `development` | |
| `preview` | internal, Android APK, `withoutCredentials` | production project | `preview` | |
| `production` | store, `autoIncrement` | production project | `production` | Android credentials `remote` in `eas.json`, switched to `local` with the injected keystore by `eas-build.yml` |

Every profile points at production. There is no build that talks to anything else.

### How expo-router is structured

- `app/_layout.tsx` loads fonts, shows an animated splash, wraps everything in `QueryProvider`, `AuthProvider` and `AuthGuard`, and handles `amari://auth-callback` deep links (`app/_layout.tsx:429-445`).
- `AuthGuard` (`app/_layout.tsx:65-118`) redirects: no session to `/(auth)`; session but no member row to an alert, sign out and `/(auth)/invite`; member not onboarded to `/(onboarding)`; onboarded to `/(tabs)`.
- `(tabs)/_layout.tsx` registers push and declares Pulse, Events, Aligned, Corridor, Me, Admin, plus hidden `discover` and `network` stubs. Visibility is computed in `components/v2/CustomTabBar.tsx:33-56` from the JWT tier claim and `lib/theme.ts:191-197`.
- `app/admin/_layout.tsx` blocks non-admins on the client. The database is the real gate.

### State and data fetching

- Server state: TanStack Query, keys in `lib/queryClient.ts`, no persistence, so an app resumed offline after five minutes has nothing cached.
- Auth state: `AuthProvider` context. Tier and admin flags come from `session.user.app_metadata`, which is only as fresh as the last token. A Realtime subscription on `notifications` refreshes the session when a `tier_change` notification arrives (`providers/AuthProvider.tsx:246-268`).
- Validation: zod schemas in `lib/schemas.ts` for registration input.
- Shared libraries worth knowing: `@gorhom/bottom-sheet`, `moti` and Reanimated 4, `expo-image`, `lucide-react-native`, `react-native-qrcode-svg`.

### Database locally

`supabase db start` builds the schema from the 58 migrations. `supabase/seed.sql` contains four
literal invitation codes including a laureate code with admin; the 22 September evidence shows none
of them exist in production (`docs/evidence/live-verification-targeted-codes-20260921.csv`). Use
it locally only, and do not copy its codes anywhere.

## Environment and access

For Algene Pulido. GitHub `algenepulido`. Google Play testing account `algene.pulido@gmail.com`.

Principles: invite him as a collaborator on each platform under his own identity, never share an
account password, grant the least role that does the job, and separate what he needs to
investigate from what he needs to ship. Status values are READY, NEEDS USER ACTION, NEEDS EXTERNAL
PLATFORM ACCESS, NOT CURRENTLY AVAILABLE, UNKNOWN / MUST VERIFY.

### The environment question comes first

There is no staging project. `eas.json:13,31,50` point development, preview and production builds at
the same Supabase project. The authorisation work in this sprint consists mostly of calls that must
fail; running them against production is possible for read-only denials but unsafe for anything
that could succeed. Three options exist; the owner must choose.

| Option | What it is | Cost and effort | Fit |
|---|---|---|---|
| Local Supabase from migrations | `supabase db start` in Docker. CI already does this on every push | Free. The schema replays (CI proves it at `3ce4c4c`). No production data, no Vault secret, no cron, no Storage objects, no Auth provider config | Best for SQL-level negative tests and pgTAP. Cannot test Apple or Google sign-in end to end |
| Separate staging Supabase project | New project, migrations applied, Edge Functions deployed, providers configured | Plan-dependent; EXTERNAL VERIFICATION REQUIRED. Needs Apple and Google redirect URLs added | Best for device testing against a realistic backend. Needs an app build pointed at it, which means a new EAS profile |
| Supabase branching | Preview branches of the production project | Plan-dependent; EXTERNAL VERIFICATION REQUIRED | Similar to staging with less setup, if the plan includes it |
| Production, read-only | Negative tests that can only be refused, run with real member JWTs | No cost | Acceptable for denials only, with the owner's agreement, never for writes |

Recommendation: local Supabase for SQL authorisation work from day one, and one staging project
for device and auth-provider work if the owner approves the cost. Production only for read-only
denials agreed in advance.

### Access matrix

| Service | Why needed | Minimum role | Needed immediately? | Current status | Who actions | Security note |
|---|---|---|---|---|---|---|
| GitHub `amari-app` | Code, branches, PRs, CI results | Collaborator with Write; branch protection on `release/v2-redesign-signed` requiring PR review | Yes | NEEDS USER ACTION. Repository has one collaborator | Jeremy, repository settings | Do not grant Admin. Actions secrets stay owner-only |
| GitHub Actions secrets | Not needed to investigate. Needed only if he must change the signed Android workflow | None; owner runs `eas-build.yml` | No | Owner-only | Jeremy | `ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `EXPO_TOKEN`, `EXPO_PUBLIC_MAPBOX_TOKEN` must not be shared |
| Supabase production project | Read schema, policies, grants, cron, logs, Storage config; confirm plan, backups, PITR, pooling | Organisation member with a read-only or developer role. Supabase role names and their exact rights are EXTERNAL VERIFICATION REQUIRED | Yes, read-only | NEEDS USER ACTION | Jeremy, Supabase dashboard | No service-role key by email or chat. No database password. SQL editor use should be read-only unless agreed |
| Supabase staging or local | Negative tests, migration rehearsal | Owner of the staging project, or local Docker | Yes | NOT CURRENTLY AVAILABLE (staging); local is READY from the repository | Jeremy decides; Algene builds | Seed synthetic data only |
| Supabase Edge Function secrets | Confirm names present, rotate if needed | Owner | No | UNKNOWN / MUST VERIFY | Jeremy | Values never leave the dashboard |
| Expo / EAS | Build logs, build profiles, environment variables, submissions | Expo organisation member with Developer role, if the project is under an organisation. It is under a personal account per `docs/releases/1.2.5-artifacts.md`; a personal account cannot add members | For builds, yes | UNKNOWN / MUST VERIFY | Jeremy | Moving the project into an Expo organisation may be needed to grant access without sharing the account |
| Apple App Store Connect | TestFlight installs; release metadata; phased release | TestFlight external or internal tester for investigation; App Manager only if he submits | Tester: yes. Submission: no | NEEDS EXTERNAL PLATFORM ACCESS. The 5 Sep report records an Individual developer account, which cannot add team members | Jeremy | If the account is Individual, he can only be a TestFlight tester or use the public App Store build. Owner submits |
| Google Play Console, testing | Install the closed-test build | Add `algene.pulido@gmail.com` to a closed-testing list on the Alpha track and send the opt-in link | Yes | DONE, added 30 Sep 2026 | Algene accepts the opt-in link | Invited is not opted in; he must accept the link. He also counts towards the 12-tester production gate |
| Google Play Console, release | Staged rollout, pre-launch report, vitals | User with release permissions scoped to this app | No, only for release | NEEDS EXTERNAL PLATFORM ACCESS | Jeremy | Do not grant account-wide admin |
| Sentry or chosen monitor | Create project, DSN, source maps | Member of a new organisation or project owned by AMARI | When observability starts, day 2 or 3 | NOT CURRENTLY AVAILABLE. No account is referenced anywhere except a placeholder in `.env.example` | Jeremy approves cost; Algene sets up | A paid tier needs owner approval |
| Mapbox | Download token for native builds; usage and cost | Own download-scoped token, or build via the owner's EAS secret | For local native builds only | UNKNOWN / MUST VERIFY | Jeremy | Never share the owner's secret token; issue a scoped token |
| Push infrastructure | Expo push service uses the EAS project credentials; APNs key and FCM credentials live in EAS | Covered by EAS access | With EAS | UNKNOWN / MUST VERIFY | Jeremy | Credentials stay in EAS |
| Apple Sign In configuration | Services ID, key, redirect URLs in Supabase Auth | Read-only view of Supabase Auth providers | For auth work | UNKNOWN / MUST VERIFY | Jeremy | The Apple key and team identifiers are credentials |
| Google Cloud OAuth clients | Web, Android and iOS client IDs, SHA-1 fingerprints, redirect URIs | Viewer on the Google Cloud project | For auth work | UNKNOWN / MUST VERIFY | Jeremy | Client secret never shared |
| Website `amarigroupau.com` | Hosts `/auth-callback` used by OAuth fallback and magic links | Read access to the page source or repository | For deep-link work | UNKNOWN / MUST VERIFY | Jeremy | |
| Email delivery for OTP | Deliverability of sign-in codes | Visibility of Supabase Auth SMTP settings | For auth work | UNKNOWN / MUST VERIFY | Jeremy | |
| Classifier provider | Only if he touches the pipeline | None | No | Not needed yet | | Keys stay in Supabase secrets |
| Vault | `news_pipeline_secret` used by pg_net triggers | None | No | | | Presence can be checked by name without reading the value |

### Investigation access against release access

| Needed to investigate and fix | Needed only to release |
|---|---|
| GitHub Write | Play Console release permissions |
| Supabase read-only on production | App Store Connect App Manager, or the owner submits |
| Local or staging Supabase with full control | EAS submit rights |
| TestFlight tester, Play closed tester | GitHub Actions run permission for `eas-build.yml` |
| EAS read access to builds and env | Supabase migration apply rights on production |
| Test identities and invitation codes on the target environment | |

Recommendation: the owner applies production migrations and runs store submissions during this
sprint, with Algene preparing the PR, the migration, the rollback and the verification queries.
That keeps privileged credentials with one person while the engineer still does the work.

## Test accounts and invitation codes

Nothing here has been created. No credentials appear in this pack. Each identity below belongs to
Algene alone, so that every action is attributable, and each is revoked at the end of the sprint.

### Decide the environment before creating anything

On production, any identity at gold or above sees the names, employers and project details of
real members, and an admin identity sees everything. The provisioning script itself warns about
this (`scripts/reviewer-account-provision.sql`, "Tier, and why the default is the low one"). Creating
identities on production is therefore a privacy decision as well as an access decision.

| Environment | Consequence for identities |
|---|---|
| Local Supabase (Docker) | Algene creates every identity himself from seed SQL. No real data. Cannot exercise Apple or Google sign-in end to end |
| Staging project | Owner or Algene creates identities; synthetic members only. Needs a staging app build for device tests |
| Production | Owner creates identities. Real members visible to gold and above, and to admin. Every write is a production write |

Recommendation: full identity set on local or staging. On production, at most one member-tier
identity for device smoke tests of sign-in and store builds, unless the owner decides otherwise
in writing.

### Existing tooling

| Tool | What it does | Touches production? |
|---|---|---|
| Admin Codes screen, `app/admin/codes.tsx`, via `admin_create_invitation_code` | Issues a single invitation at a chosen tier. Refuses admin and staff grants (`20260710000002:78`) | Yes, when used in the production app |
| `scripts/external-tester-issue.sql` | Issues personal invitations from a gitignored CSV, tracks them in `external_tester_access`, refuses platinum and laureate unless overridden, never grants admin | Yes, run with psql against production. Requires `20260922000001` applied |
| `scripts/external-tester-revoke.sql` | Suspends the tester's member row so the database refuses them | Yes |
| `scripts/reviewer-account-provision.sql` | Prepares the member side of a password account the owner creates in the Auth dashboard; default tier member; dry run by default | Yes |
| Admin Members screen, `app/admin/members.tsx`, via `change_member_tier` and `admin_set_member_status` | Changes tier and suspends | Yes |
| `supabase/seed.sql` | Local seed including literal codes | Local only. Never run against production |

There is no tooling that creates an administrator. `admin_roles` is written only by
`redeem_invitation_code`, and every issuing path now refuses admin invitations, so an admin test
identity on any shared environment requires a deliberate SQL insert by the owner.

### Identities

#### Active normal member
- **Required state:** auth user, member row `status = active`, tier `silver` (the entry tier most new members will hold), onboarded.
- **Expected permissions:** Pulse, briefing, events, own profile, issue reports, deletion request.
- **Expected denials:** Aligned tab and every Aligned data path (map RPCs, `map_cache_*` tables, projects), admin RPCs, other members' rows.
- **Exists:** No.
- **Provision safely:** invitation at silver from the Admin Codes screen or `external-tester-issue.sql`; Algene redeems it on a device with his own sign-in.
- **Touches production:** only if issued there.
- **Never:** use it to browse real members' data if the tier is later raised.

#### Lower-tier member
- **Required state:** as above at tier `member`.
- **Expected denials:** as silver, plus silver-gated tables (`city_presence` directory, `corridor_opportunities`, tile creation).
- **Exists:** No. **Provision:** invitation at member tier. **Touches production:** if issued there.

#### Higher-tier member
- **Required state:** tier `gold` minimum for Aligned; `platinum` to test early event access windows.
- **Expected permissions:** Aligned map and directory, project creation, introductions, early event access at platinum.
- **Expected denials:** admin RPCs, others' private rows, self-approval of projects.
- **Exists:** No.
- **Provision:** invitation at gold, then `change_member_tier` to platinum when needed. On production this exposes real member data; prefer staging.
- **Never:** export, screenshot or copy real member data seen through this identity.

#### Admin
- **Required state:** active member plus an `admin_roles` row with role `admin`.
- **Expected permissions:** admin screens and RPCs, `pipeline` Edge Functions via admin JWT, check-in, moderation.
- **Expected denials:** none inside the app; the database owner role remains separate.
- **Exists:** Four administrator roles exist on production (1 owner, 3 admin at 22 Sep). None belongs to Algene.
- **Provision:** on local or staging, insert the `admin_roles` row in seed SQL. On production, only by the owner, deliberately, with an expiry date recorded in `external_tester_access` or a note.
- **Never:** change a real member's tier or status, issue invitations to real people, publish Pulse content, or run check-in against a real event.

#### Suspended or inactive member
- **Required state:** member row `status` not `active` (use the value set by `admin_set_member_status`), previously active so it holds a session and an old JWT.
- **Expected denials:** every member RPC and table; the admin bypass must also fail if the account was an admin (HO-07).
- **Exists:** No.
- **Provision:** create an active member, sign in on a device to keep a session, then suspend via the Admin Members screen or `external-tester-revoke.sql`.
- **Touches production:** if done there.
- **Never:** suspend a real member to test this.

#### Admin capable of publishing Media
- **Required state:** admin as above.
- **Exists:** No, and no Media publishing workflow exists yet (see `MEDIA_V1.md`). This identity becomes useful once Media V1 has an upload path.
- **Provision:** reuse the admin identity; on production only after the Media V1 design is approved.

#### Two fresh invitation codes
- **Required state:** two unused, unexpired invitations at member or silver tier, addressed to Algene's own email addresses or unaddressed, created after 22 Sep so they use the six-character format.
- **Provision:** Admin Codes screen or `external-tester-issue.sql`. The script expects one live invitation per email, so two codes need two addresses or two runs after redemption.
- **Delivery:** send each code through a channel separate from the email that names the account, and never in a chat transcript; invitation 2068 had to be expired on 22 Sep after its code was pasted into one.
- **Touches production:** yes, if issued there.

### Revocation at sprint end

Suspend every identity (`external-tester-revoke.sql` or Admin Members), delete the admin role row,
expire any unused invitation, remove the Play tester entry if he is not continuing, and rotate any
password account in the Auth dashboard.
