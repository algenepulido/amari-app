# Operations

Monitoring, scheduled jobs, backups and alerting; then the load test plan and cost template. Commit `3ce4c4c`.

## Observability and operations

Commit `3ce4c4c`. Two columns throughout: what the code shows, and what only a dashboard can show.

### Current surface

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
| Release rollback | See `RELEASE.md` | |

### What a rebuild from the repository would not restore

- Five cron schedules (ingest, enrich, affinity fold, briefing push, project digest).
- Vault secret `news_pipeline_secret`, required by both pg_net triggers.
- Edge Function secrets and the `--no-verify-jwt` deployment flags.
- Auth provider configuration, redirect allow list, hook enablement.
- Storage bucket `public`, if it exists, and every stored object.
- `pg_net` enablement was once missing for months while crons silently failed (`20260710000007_enable_pg_net.sql` and `docs/AMARI-WORKING-MEMORY.md:266-270`). The same class of silent failure is possible again without alerting.

### Acceptance criteria for this sprint

- **Monitoring installed.** `@sentry/react-native` (or an approved equivalent) with its Expo config plugin, DSN supplied through an `EXPO_PUBLIC_` variable or app config, environment tagged by build profile, release and dist tied to the app version and build number, source maps uploaded during EAS build.
- **Deliberate test error.** From a build made with the production profile (TestFlight and Play Alpha), trigger a test error from a hidden admin-only control or a debug gesture, and a separate native test crash. Acceptance: both appear in the dashboard with a readable, symbolicated stack and the correct release. Do not trigger this in the public App Store build without the owner's agreement. This pack did not trigger any error.
- **Scrubbing.** `beforeSend` removes email addresses, JWTs, refresh tokens, invitation codes and `user_metadata`; user context carries only the member UUID. Prove it with a test event containing a fake email and token.
- **RPC failures.** Wrap the Supabase client or `reportError` so failed RPC calls report the function name and PostgREST error code, never the parameters.
- **Pipeline alerting.** At minimum a scheduled SQL check or Edge Function that flags: no article ingested for three hours during the day, enrich backlog over a threshold, monthly classifier budget above 80 per cent, any `cron.job_run_details` failure in 24 hours. Delivery channel to be agreed (email or push to admins).
- **Cron in version control.** One idempotent migration registering all nine schedules, reading the secret from Vault at run time, never inlining it. Prove it by replaying on local Supabase and listing `cron.job`.
- **Backups.** Record plan, backup frequency, PITR availability and window, and pooling mode in this file. A restore rehearsal is Phase 2 unless PITR is already available and cheap to test.

## Performance, scale and cost

No load test was run to prepare this pack. Nothing here should be run against production. Use
local Supabase or a staging project with synthetic data. Prices are not stated; every price must
come from the provider's current pricing page at the time of the estimate.

### Hot paths

#### Personalised feed: `get_news_feed`
- **Definition:** `supabase/migrations/20260718000001_reconcile_intelligence_release_schema.sql:151-250`, SECURITY DEFINER, `plpgsql`.
- **Shape:** for every published article in the last 14 days, join its source, left-join the caller's saved row, compute an interest boost with a lateral aggregate over `member_feed_interests`, an entity boost with a lateral aggregate over `member_entity_follows` joined to `tracked_entities`, exclude articles the caller hid through a `not exists` on `news_events`, compute a score, sort by the score, then `limit` and `offset`.
- **Indexes present:** `news_articles_feed_idx (status, published_at desc)`, GIN on `topics`, `regions` and `entities`, `news_events_member_idx (member_id, created_at desc)`, `news_events_article_idx (article_id)`, primary keys on `member_feed_interests (member_id, tag)` and `saved_articles (member_id, article_id)`.
- **Expected costs:** the window filter uses `coalesce(published_at, ingested_at)`, which `news_articles_feed_idx` cannot serve, so expect a scan of published rows; sort cannot use an index because it orders by a computed score; the hide check has no index on `(member_id, article_id) where event_type = 'hide'`; `OFFSET` pagination repeats the full computation for every page. `news_events` has no retention and grows with impressions.
- **Data dependencies:** window size (about 2,000 eligible rows at 5 Sep), interests per member, follows per member, hides per member, total `news_events` rows.

#### Matching: `generate_weekly_matches`
- Cron weekly (`0 19 * * 0`), SECURITY DEFINER without `search_path`, service role only. Read the body before testing; the algorithm's complexity in the number of eligible members is the key figure.

#### Push fan-out
- `send-briefing-push`: selects all active members with tokens, filters in memory, posts chunks sequentially to the Expo push API in one invocation, no receipts (`supabase/functions/send-briefing-push/index.ts:86-127`).
- `project-engagement` digest mode loops projects and followers in one invocation.

#### News pipeline
- `ingest-news`: 15 sources per run, 25 items each, 1 MB bodies, lease-protected. Scales with source count, not members.
- `enrich-news`: two batches of ten per run under a hard monthly budget. Scales with article volume, not members.

#### Map
- `map_projects`, `map_states`, `map_countries` read small cache tables; Mapbox cost scales with map loads on devices.

#### Storage and media
- No media today. Once Media V1 exists, egress per member-hour of playback becomes the dominant variable cost.

### Test plan

| Test | Method | Evidence to return |
|---|---|---|
| Feed latency | Seed 1,000, 10,000 and 100,000 synthetic members; 2,000 and 6,000 eligible articles; interests 0 to 20 per member; follows 0 to 10; hides 0 to 200; `news_events` at 1 M, 10 M and 50 M rows. Call `get_news_feed` as real `authenticated` JWTs (set `request.jwt.claims` in SQL, or through PostgREST) | `EXPLAIN (ANALYZE, BUFFERS)` for a light and a heavy member at each size; p50, p95, p99 from at least 1,000 calls; rows scanned; sort method and memory |
| Feed concurrency | 50, 200 and 500 concurrent callers with a tool such as k6 against PostgREST on staging | p50, p95, p99, error rate, database CPU, connection count |
| Pagination | Pages 1, 5 and 20 with `OFFSET` | Latency growth per page; duplicate or skipped items when scores change between pages |
| Hide anti-join | Heavy-hide member with and without a partial index `(member_id, article_id) where event_type = 'hide'` on a scratch database | Plan and timing difference |
| Matching | Run `generate_weekly_matches` at 1,000 and 10,000 eligible members | Duration, locks held, rows written |
| Push fan-out | `send-briefing-push` on staging against 1,000 and 10,000 synthetic tokens pointed at a stub endpoint, never the real Expo API with fake tokens | Duration against the Edge Function time limit; failure behaviour when a chunk fails |
| Pipeline headroom | Source catalogue at three times its size on staging | Lease behaviour, budget behaviour, run duration |
| Failure behaviour | Kill the database connection mid-feed; exhaust the classifier budget; make one source time out | What the member sees; what is logged |

Dataset assumptions to state with every result: article window, members, interests, follows,
hides, events rows, compute size, pooler mode. Concurrency assumptions: peak concurrent members
as a share of total (state the share used, for example 5 and 10 per cent).

### Cost-model input template

Fill from provider pricing pages and measured usage. Leave a cell empty rather than guess.

| Driver | Unit | Measured usage per member per month | 1,000 members | 10,000 members | 100,000 members | Price source (URL and date) | Notes |
|---|---|---|---|---|---|---|---|
| Supabase plan base | per month | | | | | EXTERNAL | Current plan unknown |
| Supabase compute | instance size needed at peak concurrency | | | | | EXTERNAL | From the concurrency test |
| Database size | GB | | | | | EXTERNAL | 59 MB at 5 Sep, 18 MB of it news |
| Database egress | GB | | | | | EXTERNAL | Feed payloads dominate |
| Storage size | GB | | | | | EXTERNAL | Media V1 |
| Storage egress | GB | | | | | EXTERNAL | Media minutes x bitrate |
| Edge Function invocations | count | | | | | EXTERNAL | Mostly fixed by cron, not members |
| Auth monthly active users | count | | | | | EXTERNAL | |
| Realtime | connections, messages | | | | | EXTERNAL | Tier-change subscription per session |
| Mapbox | map loads or MAU per SDK terms | | | | | EXTERNAL | Aligned tab users only |
| Media delivery | GB or minutes | | | | | EXTERNAL | Only if a provider is approved |
| Push | messages | | | | | EXTERNAL | Expo push pricing and limits |
| News classification | USD per month | | | | | `news_ai_spend` | Scales with articles, capped by code |
| Email for OTP | messages | | | | | EXTERNAL | Supabase mailer limits or SMTP provider |
| Sentry or equivalent | events, seats | | | | | EXTERNAL | Needs approval |
| EAS | builds, plan | | | | | EXTERNAL | |
| Apple and Google developer programmes | per year | | | | | EXTERNAL | Fixed |
