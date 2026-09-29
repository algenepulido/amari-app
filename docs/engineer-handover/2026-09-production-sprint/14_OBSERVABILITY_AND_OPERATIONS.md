# Observability and operations

Commit `3ce4c4c`. Two columns throughout: what the code shows, and what only a dashboard can show.

## Current surface

| Area | Visible in code | Requires dashboard verification |
|---|---|---|
| Crash and error reporting | None installed. `lib/sentry.ts` and `lib/posthog.ts` are guarded no-ops that `require()` an SDK absent from `package.json` | Whether any Sentry or PostHog project exists |
| Error boundaries | Root `ErrorBoundary` wraps the app (`app/_layout.tsx`, `components/ErrorBoundary.tsx:16`) and calls `reportError` | |
| Global JS handler | `installGlobalErrorHandler()` chains `ErrorUtils` to `reportError`, which logs to `console.error` (`lib/reportError.ts`) | |
| Native crash capture | None | Xcode Organizer crashes; Play Android vitals |
| API and database error capture | Individual `console.error` calls; no central RPC error reporting; many queries surface errors only to TanStack Query state | Supabase API logs |
| Source maps | Not configured | EAS build artefacts |
| Sensitive data filtering | `reportError` spreads arbitrary context into the log; `AuthProvider` logs raw RPC errors. With a real SDK these could carry emails or tokens unless scrubbed | |
| Logs | Edge Functions log with `console.error` and prefixes such as `[briefing-push]` | Supabase Edge Function logs, retention by plan |
| Scheduled jobs | 4 in migrations, 5 more in production only (PR5-10) | `cron.job`, `cron.job_run_details` |
| Health checks | None. `NEWS-PIPELINE.md:95` describes a manual staleness check | |
| News ingestion | Lease, bounded fetch, SSRF guards; results returned as JSON to the caller (cron) | Function logs; `news_articles.ingested_at` freshness |
| Classifier pipeline | Hard monthly budget with reservations and settlement (`enrich-news`); model pinned in code | `news_ai_spend`; provider billing |
| Push failures | Chunk failures logged; no receipt polling; no dead-token pruning (PR5-07) | Expo push receipts |
| Cron failures | Nothing alerts | `cron.job_run_details` |
| Alerting | None | |
| Backups and PITR | Nothing in code | Plan, backup schedule, PITR window (PR5-23) |
| Pooling | Client uses PostgREST; no direct connections from the app. The owner's psql sessions used the session pooler per the containment record | Pooler mode and limits, compute size |
| Recovery | Migrations replay on an empty database (CI proves this at `3ce4c4c`), but five schedules, the Vault secret, Storage objects, Auth provider settings and Edge Function secrets are outside the repository | |
| Release rollback | See `17` | |

## What a rebuild from the repository would not restore

- Five cron schedules (ingest, enrich, affinity fold, briefing push, project digest).
- Vault secret `news_pipeline_secret`, required by both pg_net triggers.
- Edge Function secrets and the `--no-verify-jwt` deployment flags.
- Auth provider configuration, redirect allow list, hook enablement.
- Storage bucket `public`, if it exists, and every stored object.
- `pg_net` enablement was once missing for months while crons silently failed (`20260710000007_enable_pg_net.sql` and `docs/AMARI-WORKING-MEMORY.md:266-270`). The same class of silent failure is possible again without alerting.

## Acceptance criteria for this sprint

- **Monitoring installed.** `@sentry/react-native` (or an approved equivalent) with its Expo config plugin, DSN supplied through an `EXPO_PUBLIC_` variable or app config, environment tagged by build profile, release and dist tied to the app version and build number, source maps uploaded during EAS build.
- **Deliberate test error.** From a build made with the production profile (TestFlight and Play Alpha), trigger a test error from a hidden admin-only control or a debug gesture, and a separate native test crash. Acceptance: both appear in the dashboard with a readable, symbolicated stack and the correct release. Do not trigger this in the public App Store build without the owner's agreement. This pack did not trigger any error.
- **Scrubbing.** `beforeSend` removes email addresses, JWTs, refresh tokens, invitation codes and `user_metadata`; user context carries only the member UUID. Prove it with a test event containing a fake email and token.
- **RPC failures.** Wrap the Supabase client or `reportError` so failed RPC calls report the function name and PostgREST error code, never the parameters.
- **Pipeline alerting.** At minimum a scheduled SQL check or Edge Function that flags: no article ingested for three hours during the day, enrich backlog over a threshold, monthly classifier budget above 80 per cent, any `cron.job_run_details` failure in 24 hours. Delivery channel to be agreed (email or push to admins).
- **Cron in version control.** One idempotent migration registering all nine schedules, reading the secret from Vault at run time, never inlining it. Prove it by replaying on local Supabase and listing `cron.job`.
- **Backups.** Record plan, backup frequency, PITR availability and window, and pooling mode in this file. A restore rehearsal is Phase 2 unless PITR is already available and cheap to test.
