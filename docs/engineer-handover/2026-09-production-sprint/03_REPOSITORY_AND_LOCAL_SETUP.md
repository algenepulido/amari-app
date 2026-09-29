# Repository and local setup

Every command below was checked against `package.json`, `eas.json`, `.github/workflows/ci.yml` and
`.husky/` at commit `3ce4c4c`. Commands marked OBSERVED were run on 29 September 2026 in a clean
worktree on Windows 11 with Node 24.12.0; the rest are read from configuration and not run.

## Stale guidance you will meet in the repository

Implementation wins over these. Each is also in `06` as a documentation finding.

- `README.md`, `CLAUDE.md` and `AGENTS.md` say new invitation codes are 48 characters. Migration `20260922000002_short_codes_and_validation_throttle.sql:46-78` changed the generator to six Crockford base32 characters, and that migration ran against production according to `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`.
- `CLAUDE.md` and `AGENTS.md:84-89` say to work in `C:\amari-ui-build` on the release branch. That is the owner's machine layout, and that worktree is on a different branch today. For you: clone, check out `release/v2-redesign-signed`, branch from it.
- `supabase/functions/NEWS-PIPELINE.md:34` says to set `OPENAI_MODEL`; the code rejects that override.
- `master` is the GitHub default branch and is 131 commits behind the release line. PR #5 (`release/v2-redesign-signed` into `master`) has been open since March. Do not merge or close it without the owner.

## Layout

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

## Configuration files

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

## Required local software

| Tool | Version guidance | Source |
|---|---|---|
| Node | CI uses 20 (`ci.yml`), the Android build uses 22 (`eas-build.yml`). No `engines` field or `.nvmrc`. Gates also passed on 24.12.0 locally. Use 20 or 22. | workflows |
| npm | Lockfile is `package-lock.json`; use `npm ci` | repository |
| EAS CLI | `eas.json` requires `>= 10.0.0`; 18.4.0 worked locally | `eas.json:3` |
| Deno | 2.x | `ci.yml` |
| Supabase CLI | CI pins 2.109.1 | `ci.yml` |
| Docker | Needed for `supabase db start` and the P0 fixtures | `ci.yml`, `supabase/verification/p0/README.md` |
| Xcode and Android Studio | For development builds on simulators and devices | Expo standard |

## Environment variable names

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

## Commands

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
| Mobile flow script | `npm run test:mobile-flows` | Do not run as is: `scripts/verify-mobile-flows.mjs` embeds a burned production invitation code and a named person's email, and targets production |
| Production dependency audit | `npm audit --omit=dev` | OBSERVED: 34 advisories, 2 critical, 10 high. Whether any reaches the shipped bundle is UNVERIFIED |

## EAS build profiles

| Profile | Distribution | Supabase target | Channel | Notes |
|---|---|---|---|---|
| `development` | internal, dev client | production project | `development` | |
| `preview` | internal, Android APK, `withoutCredentials` | production project | `preview` | |
| `production` | store, `autoIncrement` | production project | `production` | Android credentials `remote` in `eas.json`, switched to `local` with the injected keystore by `eas-build.yml` |

Every profile points at production. There is no build that talks to anything else.

## How expo-router is structured

- `app/_layout.tsx` loads fonts, shows an animated splash, wraps everything in `QueryProvider`, `AuthProvider` and `AuthGuard`, and handles `amari://auth-callback` deep links (`app/_layout.tsx:429-445`).
- `AuthGuard` (`app/_layout.tsx:65-118`) redirects: no session to `/(auth)`; session but no member row to an alert, sign out and `/(auth)/invite`; member not onboarded to `/(onboarding)`; onboarded to `/(tabs)`.
- `(tabs)/_layout.tsx` registers push and declares Pulse, Events, Aligned, Corridor, Me, Admin, plus hidden `discover` and `network` stubs. Visibility is computed in `components/v2/CustomTabBar.tsx:33-56` from the JWT tier claim and `lib/theme.ts:191-197`.
- `app/admin/_layout.tsx` blocks non-admins on the client. The database is the real gate.

## State and data fetching

- Server state: TanStack Query, keys in `lib/queryClient.ts`, no persistence, so an app resumed offline after five minutes has nothing cached.
- Auth state: `AuthProvider` context. Tier and admin flags come from `session.user.app_metadata`, which is only as fresh as the last token. A Realtime subscription on `notifications` refreshes the session when a `tier_change` notification arrives (`providers/AuthProvider.tsx:246-268`).
- Validation: zod schemas in `lib/schemas.ts` for registration input.
- Shared libraries worth knowing: `@gorhom/bottom-sheet`, `moti` and Reanimated 4, `expo-image`, `lucide-react-native`, `react-native-qrcode-svg`.

## Database locally

`supabase db start` builds the schema from the 58 migrations. `supabase/seed.sql` contains four
literal invitation codes including a laureate code with admin; the 22 September evidence shows none
of them exist in production (`docs/evidence/live-verification-targeted-codes-20260921.csv`). Use
it locally only, and do not copy its codes anywhere.
