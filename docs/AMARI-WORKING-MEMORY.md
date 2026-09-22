# AMARI Working Memory

> ## Production security change, 22 September 2026
>
> A P0 invitation vulnerability was found live and **contained in production** on
> 2026-09-22T01:15Z. Invitation codes, invitation grants, the three map functions and
> function privileges all changed. **Read `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`
> before touching any of them.**
>
> The short version, because these will mislead you otherwise:
> the predictable bootstrap codes are all **expired** (1,216 of them, so 2,029 expired rows
> is correct, not corruption); new invite codes are **48 characters** after the prefix, not 8;
> `redeem_invitation_code` now binds to `auth.uid()` and refuses a mismatched `p_user_id`;
> `anon` and PUBLIC are revoked from redemption, the map trio and the rate limit pair, with
> `anon` retaining only `validate_invitation_code`; the map functions now enforce active
> membership at gold or above **server side**; and new functions in `public` no longer default
> to a PUBLIC grant.
>
> **Never run section 1 of `scripts/rollback-p0-invitation-containment.sql`** — it would revive
> all 1,216 weak invitations.


**Last reconciled against the code: 2026-07-17**, at release head `c6eee96`
(v1.2.4). The previous version of this file was dated 2026-05-11 and described
v1.1.2 — it was two months behind and would have misled anyone who trusted it.
Treat everything here as a point-in-time record. Check `git log`,
`npx eas build:list`, and the code itself before relying on a specific claim.

This file preserves shared working context so a future Codex, Claude, or other
agent session can resume without chat history.

## Collaboration Ethos

AMARI is built for a high-trust, culturally ambitious community. It should feel
like AMARI, not a generic Expo starter.

- Push the product envelope where it creates a better member experience.
- Speed is not carelessness. Product taste sits on top of disciplined release
  engineering, privacy, security, and review compliance.
- Prefer bold, sharp, intentional interactions over safe average UI.
- If a premium interaction is too risky for the immediate release, ship the
  stable baseline and document the stronger future version.
- Treat privacy and trust as product features, not compliance paperwork.
- Keep Apple/Google reviewers, employee testers, and future members in mind at
  the same time.

## Standing Rules

- **PRs always.** Never commit directly to `release/v2-redesign-signed`.
- **Never edit app runtime code without explicit per-task approval from Tapiwa.**
  Reading is fine. Writing needs a yes, every time.
- **Real data or an honest empty state.** Never invent numbers, matches, people,
  partnerships, or events. Never tell a member the app did something it did not.
- Keep release work on isolated branches/worktrees when another agent may be
  active. Check `git branch --show-current` before branch-mutating operations.
- Conventional Commits. Author email `tapiwanashenyerenyere@gmail.com`.
- Do not revert user or other-agent work unless asked.
- Save durable decisions in GitHub docs, not only local notes.

## Current State — v1.2.4

Release branch `release/v2-redesign-signed`, head `c6eee96` (11 Jul 2026). Both
platforms shipped: Android build 60 to the Play closed-testing Alpha track, iOS
build 35 to App Store review. **This is the version members are running.**

Supabase project `eavnuxccdxqyzvnspmaq`. 48 migrations. Six edge functions.

What is live: invite/OTP auth with Apple and Google sign-in; Aligned (Mapbox
project map, Spotify-style shelves, consented introductions); Events with QR
ticketing and an admin check-in scanner; Pulse (hand-written editions **and** an
algorithmic news briefing); the intelligence feed with LLM classification;
entity tracking; push notifications; in-app issue reporting with admin fan-out;
five-tier membership.

### What shipped between 1.1.2 (May) and 1.2.4 (July)

| PR | What |
|---|---|
| #41 | Intelligence feed foundation + event ticketing |
| #45 | Motion system (`lib/motion`), project pages, journal timeline |
| #46/#47 | LLM provider adapter, budget/batch fixes |
| #48 | Pulse digest home + dedicated Briefing screen, video-ready content model, project shelves, map polish |
| #50 | Gold tier, entity intelligence, briefing visibility, push system, project engagement loop |
| #52 | In-app issue reporting + admin fan-out, **pg_net fix** |
| #54 | Testing/hardening baseline: tests, CI gate, error boundary, zod |

## How The Briefing Actually Works

There is **no autonomous agent** doing news discovery. It is a deterministic
pipeline: cron fires two edge functions, one fetches RSS, the other makes a
single classifier call per batch. The intelligence lives in the ranking SQL and
the classifier prompt, not in an agent loop. That is deliberate — cheap,
auditable, capped.

**Fetch** — `supabase/functions/ingest-news`. Pulls RSS/Atom from 12 seeded
`news_sources` across Africa, Americas, UK, and Australia. Caps at 25 items per
source, 15s timeout, identifies as `AMARI-App-Feed/1.0`. Dedupes on a `url_hash`
unique constraint. Failing feeds increment `fail_count` and fail soft.

The twelfth source is the important one: a **Google News RSS search query** for
`"African Australian" (business OR founder OR entrepreneur)`, weighted **1.20**
— the highest of any source. It exists because there are no machine-readable
African-Australian business outlets, so the Australian layer is synthesised from
a search query rather than a publication.

**Only headline, snippet, image, and link are stored. Never full article text.**
That is the copyright posture, encoded in the schema.

The same function runs an entity pass: rotates through 10 least-recently-checked
`tracked_entities` per run, 5 items each via per-entity Google News queries. When
an entity query rediscovers an existing URL it calls `append_article_entity` to
merge the tag onto the existing row rather than duplicating.

**Classify** — `supabase/functions/enrich-news`. Takes `status = 'pending'` rows
in queue groups of 10, `MAX_BATCHES_PER_RUN = 2`, with each article isolated in
its own bounded model request so publisher text cannot affect sibling results.
The LLM returns per article: 1–3
topic tags, 1–2 region tags, a 0–100 diaspora relevance score, and a one-sentence
summary in Australian English. Articles scoring **≥ 25** (`RELEVANCE_FLOOR`) flip
to `published`; below that they go to `hidden` — ingested, never shown. Roughly a
quarter get filtered out.

Provider is swappable via `LLM_PROVIDER`. **Production runs OpenRouter with
GLM-5.2**, not Claude, though the Anthropic path (Haiku 4.5) stays wired.
`HARD_MONTHLY_BUDGET_USD = 10.0` is hard-coded by design — not an env var. Spend
is metered in `news_ai_spend`; at the ceiling, enrichment stops and articles
accumulate as pending until the month rolls over. Meter rates are deliberately
conservative so the ceiling trips early.

**Rank** — `get_news_feed`. Pure SQL. No LLM, no embeddings, no vector search:

```
exp(-hours_old / 48)                      -- recency, 48h exponential decay
  × source.default_weight                  -- editorial trust in the outlet
  × (0.5 + relevance / 100)                -- classifier judgment  → [0.5, 1.5]
  × (1.0 + least(tag_boost, 2.0))          -- declared + learned interests → [1.0, 3.0]
  × (1.0 + least(entity_boost, 1.5))       -- followed entities → [1.0, 2.5]
```

`tag_boost` = sum of `member_feed_interests.weight` over tags matching the
article's topics or regions, dampened ×0.35. `entity_boost` = 0.75 per followed
entity found in `a.entities`. Articles older than **14 days** are excluded
outright, as is anything the member has hidden.

Every member reads the same published pool. What differs is **ordering**, plus
the reason label and the hide filter. Nobody sees a story nobody else could see,
and no per-member text is generated.

**Learn** — `record_news_events` captures impressions, opens, dwell, saves, and
hides, batched client-side via `lib/newsEvents.ts`. The client names only the
event type; **values are assigned server-side** (impression 1, open 2, dwell 2,
save 3, unsave 0, hide −3) so a tampered client cannot inflate its own signals.
Capped at 100 events per call.

`fold_feed_affinities()` folds two days of engagement into learned tag weights:

```
weight = least(greatest(old_weight * 0.9 + new_signal, 0.0), 5.0)
```

The 0.9 decay means stale interests fade. Crucially, the fold only touches rows
where `declared = false` — **a member's explicit choices are never overwritten by
the algorithm.** `service_role` only; never client-callable.

**Surface.** Pulse home is a digest (hero + bridge + `BriefingPreview` with
interest and entity-follow controls), not an endless list. The full feed is at
`app/briefing.tsx`. Each row carries a reason label from `lib/contentMeta.ts` —
eligible followed entity first, then a declared topic/region, then the source.
This is the trust mechanic: you always know why something reached you, and the
reason is computed from real member state.

**Push.** `send-briefing-push` self-regulates on two gates:
`MIN_DAYS_BETWEEN_SENDS = 3` **and** `MIN_FRESH_ARTICLES = 8`. At most one push
every three days, and only when there is genuinely something new. Respects
`notification_preferences.pulse`. Sends via the Expo push API in chunks of 90.

**Cadence.** Ingest at `:05,:50`, enrich at `:15,:45` (staggered so fetching
lands before classification), affinity fold at 16:30 UTC (02:30 AEST), briefing
push 22:00 UTC (08:00 AEST), engagement digest 21:30 UTC. Both pipeline functions
deploy `--no-verify-jwt` and authenticate on an `x-amari-pipeline-secret` header
or an admin JWT.

**No paid news API anywhere.** Free RSS/Atom plus Google News's public search
endpoint. The entire external-content supply costs nothing but the capped
classifier calls.

## Resolved Defects

**Fabricated Pulse profile-match footer — resolved 17 July 2026.** Removed the
profile-only helper and its complete prop/render/style cascade from both Pulse
article modal paths. There is no replacement line: hand-authored editions now
end with their actual editorial content. A repository-wide regression test
blocks the fabricated phrase and stale symbols from returning.

**Onboarding briefing interests — resolved 17 July 2026.** The five-step
post-auth flow now captures all ten member-facing topics and four regions. Its
hardened RPC accepts active or pending members and keeps learned affinities.

**Entity follows had no client UI — resolved 17 July 2026.** Both Briefing
surfaces now open the full-screen approved catalogue. Follows survive retirement
but only active approved entities boost ranking or produce `matched_entity`.

## Known Defects

Verified against the code on 2026-07-17. All open.

**News-pipeline cron is not in version control.** `20260301000005_cron_jobs.sql`
registers four crons (aligned matches, daily seed, rate-limit cleanup, match
expiry) — and `20260326000002` contains a `weekly-map-refresh` block that is
**commented out**. The news ingest, enrich, and affinity-fold schedules exist
only as copy-paste SQL in `supabase/functions/NEWS-PIPELINE.md`. Worse, the
**briefing-push and engagement-digest schedules are documented nowhere at all** —
they run in production but no migration and no runbook defines them; their
existence is only inferable from code comments. Restore this project from
migrations and the pipeline comes up dark: tables and functions present, nothing
firing. The repo already has the file and pattern to fix this.

**`components/TierGate.tsx` carries a stale four-tier map that omits gold.**
`{ member: 1, silver: 2, platinum: 3, laureate: 4 }` against the canonical
`{ member: 1, silver: 2, gold: 3, platinum: 4, laureate: 5 }`. **Nothing imports
it** — verified by grep — so it causes no live bug today. But wiring it up as-is
would evaluate a gold member (canonical level 3) as platinum (its level 3) and
silently grant platinum access. Delete it or fix it; do not use it.

**Corridor tab is hidden from everyone.** `lib/theme.ts` sets
`TAB_VISIBILITY.corridor = 99`; `CustomTabBar` hides any tab where
`requiredLevel >= 99`. `lib/constants.ts` says `2`, but the tab bar reads
`theme.ts`, so that value is dead. The screen exists and renders waitlist copy;
nobody can reach it. Intentional or not, it is worth a decision.

**Two design-token systems coexist.** `lib/constants.ts` (legacy "V7") and
`lib/theme.ts` (current "V2") both define tiers and tokens. Numbering agrees;
labels do not (`'Gold'` vs `'GOLD MEMBER'`). `app/admin/*` still reads
`constants.ts`. Consolidate eventually.

**Crash reporting is inactive.** `lib/sentry.ts` and `lib/posthog.ts` are guarded
shims that `require()` their SDK only if a DSN/key exists — and neither
`@sentry/react-native` nor `posthog-react-native` is in `package.json`. All
exports are no-ops; `lib/reportError.ts` falls back to `console.error`. Native
crash visibility is therefore absent. Activating means dependency + Expo plugin +
DSN + a new native build.

**Version drift.** `package.json` says `1.2.3`; `app.json` says `1.2.4`. The
bump touched only `app.json`. Expo reads `app.json` so store builds are correct,
but anything reading `package.json` gets the wrong answer.

**Orphaned dead code.** `components/pulse/IntelligenceFeed.tsx` — unexported,
unimported, a PR #48 deletion that did not stick. Compiles harmlessly.

**Test coverage is logic-only.** Six Jest specs, `testEnvironment: 'node'`, all
pure helpers. No component-render tests exist despite
`@testing-library/react-native` being installed. CI (`ci.yml`) does gate every
PR and push on lint → typecheck → verify:security → test.

## The pg_net Lesson

`pg_net` was **never enabled** on project `eavnuxccdxqyzvnspmaq` until 10 July.
`net.http_post` did not resolve, so every cron and every notify trigger silently
failed. The feed only stayed current because it was being curled manually. Fixed
via `create extension pg_net` and migration `20260710000007`.

Nobody noticed for months. The undocumented-cron problem above is the same class
of failure waiting to recur — production state that exists nowhere in the repo,
failing quietly.

## Product Direction

**Approved strategy (10 Jul).** Gold tier sits between silver and platinum
(shipped). After ~6 months, public app membership at $19.99/mo for below-gold —
note in-app digital subscriptions must use Apple/Google IAP (15–30% cut);
event tickets stay Stripe (physical goods). Membership rises via engagement and
real-world success; elevation is a desk decision assisted by score, **never
automatic**.

**Aggregation rules.** Published AMARI-voice synthesis aggregates to
company/industry level. Name individuals only from genuinely public record, with
a link, sparingly. Never imply relationship or awareness. Three-tier firewall:
private notes name-specific, member briefings aggregate and cite, public
archetypes only. Bake this into any drafting-engine prompt and the desk gate.

**No LinkedIn scraping, ever.** No credentials, no scraping (hiQ/Proxycurl
precedent) — it contradicts the consent-first strategy. Public posts via search
APIs only, storing headline + snippet + link-out.

**Build order.** Entity follow UI → podcasts + persistent mini-player → the
`membership_signals` ledger + structured project milestones → video originals +
paid tier. The `media_type` enum (article/editorial/video/audio/digest) is
already shipped and the ranking is format-blind, so adding podcasts is a format
flag plus a player primitive.

**Deferred: the 3D onboarding object.** Current onboarding captures six-axis
member signal in a 2D radar graph — the safer closed-testing path. The deferred
idea is a 3D-feeling six-dimensional identity object where members pull vertices
toward `Founder`, `Investor`, `Operator`, `Creator`, `Domain Specialist`,
`Artist`. Keep the data model six-dimensional even if the screen is a projection.
Store final axis values and selected answers only — never raw gesture trails. Ask
Tapiwa whether it is time before any wider open launch.

## Security Posture

Full detail in `docs/SECURITY-HARDENING-ROADMAP.md`.

- No wider invite distribution until RLS and onboarding security checks pass.
- No service-role keys in bundled iOS/Android code.
- No sensitive logs, screen replay, or raw onboarding gesture trails.
- Device trust should influence risk, not become a brittle single gate.
- The onboarding graph is an evidence ledger and matching signal, not a hidden
  human-value score.
- Never expose individual member scores to partners.
- No commercial use of member data before a consent basis exists.

## Mapbox Attribution

Do not set `logoEnabled={false}` or `attributionEnabled={false}`. A release
verifier guards this. Maps using Mapbox SDK/styles/data must keep the wordmark
and attribution visible and legible. Position and styling can be adjusted within
the allowed controls; the mark cannot be removed. If AMARI wants no visible
Mapbox mark, choose a compliant provider path rather than hiding attribution.

## Useful Commands

```bash
npm run verify:release                    # eslint + typecheck + expo config
npm run test                              # jest
npx supabase migration list               # check local vs remote history
npx supabase db push                      # apply migrations to prod
npx supabase db query --file x.sql --linked   # run SQL against prod
```

Release commands live in `docs/RELEASE-WORKFLOW.md`. Do not improvise them —
Android has a signing trap that has cost real failed submits.
