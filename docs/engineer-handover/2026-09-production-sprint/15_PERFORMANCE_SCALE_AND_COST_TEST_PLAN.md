# Performance, scale and cost test plan

No load test was run to prepare this pack. Nothing here should be run against production. Use
local Supabase or a staging project with synthetic data. Prices are not stated; every price must
come from the provider's current pricing page at the time of the estimate.

## Hot paths

### Personalised feed: `get_news_feed`
- **Definition:** `supabase/migrations/20260718000001_reconcile_intelligence_release_schema.sql:151-250`, SECURITY DEFINER, `plpgsql`.
- **Shape:** for every published article in the last 14 days, join its source, left-join the caller's saved row, compute an interest boost with a lateral aggregate over `member_feed_interests`, an entity boost with a lateral aggregate over `member_entity_follows` joined to `tracked_entities`, exclude articles the caller hid through a `not exists` on `news_events`, compute a score, sort by the score, then `limit` and `offset`.
- **Indexes present:** `news_articles_feed_idx (status, published_at desc)`, GIN on `topics`, `regions` and `entities`, `news_events_member_idx (member_id, created_at desc)`, `news_events_article_idx (article_id)`, primary keys on `member_feed_interests (member_id, tag)` and `saved_articles (member_id, article_id)`.
- **Expected costs:** the window filter uses `coalesce(published_at, ingested_at)`, which `news_articles_feed_idx` cannot serve, so expect a scan of published rows; sort cannot use an index because it orders by a computed score; the hide check has no index on `(member_id, article_id) where event_type = 'hide'`; `OFFSET` pagination repeats the full computation for every page. `news_events` has no retention and grows with impressions.
- **Data dependencies:** window size (about 2,000 eligible rows at 5 Sep), interests per member, follows per member, hides per member, total `news_events` rows.

### Matching: `generate_weekly_matches`
- Cron weekly (`0 19 * * 0`), SECURITY DEFINER without `search_path`, service role only. Read the body before testing; the algorithm's complexity in the number of eligible members is the key figure.

### Push fan-out
- `send-briefing-push`: selects all active members with tokens, filters in memory, posts chunks sequentially to the Expo push API in one invocation, no receipts (`supabase/functions/send-briefing-push/index.ts:86-127`).
- `project-engagement` digest mode loops projects and followers in one invocation.

### News pipeline
- `ingest-news`: 15 sources per run, 25 items each, 1 MB bodies, lease-protected. Scales with source count, not members.
- `enrich-news`: two batches of ten per run under a hard monthly budget. Scales with article volume, not members.

### Map
- `map_projects`, `map_states`, `map_countries` read small cache tables; Mapbox cost scales with map loads on devices.

### Storage and media
- No media today. Once Media V1 exists, egress per member-hour of playback becomes the dominant variable cost.

## Test plan

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

## Cost-model input template

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
