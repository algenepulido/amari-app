# AMARI Mobile App

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


An invite-only mobile app for the African diaspora professional community —
Australia first. React Native (Expo SDK 54) with a Supabase backend.

**Agents: read `AGENTS.md` before changing anything.** It carries the worktree
layout, the operating rules, and the current list of known defects.

Last reconciled against the code: **2026-07-17**, release head `c6eee96`
(v1.2.4). Check `git log` before trusting specifics.

## Where To Work

The release line is `release/v2-redesign-signed`, checked out at
**`C:\amari-ui-build`**. The OneDrive checkout sits on an older branch and does
**not** contain the news feed, entity engine, or push system — searching it will
tell you those features do not exist. See `AGENTS.md` for the full worktree table.

## Principles

- **Membership is earned.** Elevation is a desk decision assisted by engagement
  signal, never automatic.
- **AMARI curates.** No user-generated content in the editorial surfaces.
- **Privacy by default.** Mutual-consent connections, double opt-in
  introductions, per-section visibility toggles.
- **Real data or an honest empty state.** Never invent numbers, matches, or
  claims about what the app did for a member.
- **No gender fields. No job titles.** Names only.
- **Premium, not template.** Luxury aesthetic, no promo spam.

## Tech Stack

| Concern | Choice |
|---|---|
| Framework | Expo `~54.0.33`, React `19.1.0`, React Native `0.81.5` |
| Navigation | `expo-router` `~6.0.23` (file-based; no separate React Navigation) |
| Data | `@tanstack/react-query` `^5.90.20` over Supabase RPCs |
| State | `zustand` `^5.0.10` (local use) |
| Backend | Supabase (Postgres + RLS + Edge Functions + pg_cron + pg_net) |
| Animation | `moti` `^0.30.0` + `react-native-reanimated` `~4.1.1` |
| Maps | `@rnmapbox/maps` `^10.3.0` |
| Auth | `supabase-js`, `expo-apple-authentication`, Google Sign-In, `expo-secure-store` |
| Notifications | `expo-notifications` `~0.32.17` |
| Validation | `zod` `^4.4.3` |
| Tests | Jest `^29.7.0` + `jest-expo`, node environment |

**Crash reporting is not active.** `lib/sentry.ts` and `lib/posthog.ts` are
guarded shims that dynamically `require()` their SDK only if a DSN/key env var
is present — and neither `@sentry/react-native` nor `posthog-react-native` is in
`package.json`. Every export is a safe no-op today; `lib/reportError.ts` falls
back to `console.error`. Activating Sentry means adding the dependency, the Expo
plugin, a DSN, and a new native build.

## Tab Structure

Registered in `app/(tabs)/_layout.tsx`, labelled in `components/v2/CustomTabBar.tsx`:

| Tab | Route | Gate |
|---|---|---|
| Pulse | `index` | all members — news/briefing home |
| Events | `events` | all members |
| Aligned | `aligned` | tier level ≥ 3 |
| Corridor | `corridor` | **hidden from everyone** — see below |
| Me | `profile` | all members |
| Admin | `admin` | admins only (`href: null` otherwise) |

`discover.tsx` and `network.tsx` still exist as bare `<View />` stubs with
`href: null`. They are unreachable legacy. There is no Home/Discover/Network
triad — that was the January design.

**Corridor is dark for everyone.** `lib/theme.ts` sets `TAB_VISIBILITY.corridor
= 99` and `CustomTabBar` hides any tab where `requiredLevel >= 99`.
`lib/constants.ts` sets it to `2`, but the tab bar reads `theme.ts`, so that
value does nothing. The screen exists and renders waitlist copy; nobody can
reach it.

## Membership Tiers

Five tiers, coded in `lib/constants.ts` and `lib/theme.ts`:

```
member (1) → silver (2) → gold (3) → platinum (4) → laureate (5)
```

Gold was added in July between silver and platinum. Tier-gated content opens at
level ≥ 3 (gold and above); event early access is pinned to platinum.

Note two live inconsistencies: `lib/constants.ts` and `lib/theme.ts` agree on
numbering but disagree on labels (`'Gold'` vs `'GOLD MEMBER'`), and
`components/TierGate.tsx` carries its own **stale four-tier map that omits gold
entirely**. `TierGate` is currently unused — nothing imports it — so it causes no
live bug, but wiring it up as-is would silently grant gold members platinum
access. Delete it or fix it; do not use it.

## Repo Layout

```
app/                     Expo Router screens
├── (auth)/              landing, invite, register, welcome, auth-callback
├── (onboarding)/        post-auth onboarding (archetype quiz — not feed interests)
├── (tabs)/              Pulse, Events, Aligned/*, Corridor, Me, Admin
├── admin/               admin stack: members, events, codes, pulse, aligned, issues, checkin
└── briefing.tsx         full news briefing feed (pushed, outside the tab bar)

components/
├── aligned/             map, shelves, project page, filters, match reveal
├── pulse/               article rows, briefing preview, interest sheet, hero carousel
├── events/              event cards, ticket modal
├── badges/  ui/  v2/    tier badge, glass/grain primitives, the V2 design system
└── ErrorBoundary.tsx    class boundary → lib/reportError

lib/                     theme + constants, motion, daypart, contentMeta, pulse,
                         newsEvents, push, projectCategories, mapbox, supabase,
                         auth helpers, schemas (zod), reportError, sentry/posthog shims
queries/                 React Query hooks per domain (news, pulse, projects, events, …)
hooks/                   feature hooks (map viewport, briefing actions, project create, …)
supabase/
├── migrations/          48 migrations — see docs/SUPABASE-MIGRATION-HISTORY.md
└── functions/           ingest-news, enrich-news, send-briefing-push,
                         project-engagement, notify-admins, refresh-map-data
scripts/                 verify-release, verify-security, flow/regression guards
__tests__/               6 pure-logic Jest specs
```

## Two Systems Both Called "Pulse"

This trips people up. They are unrelated:

- **Pulse editions** — hand-authored weekly digests in `pulse_editions`, written
  through `app/admin/pulse.tsx`, served by `get_pulse_feed`/`get_pulse_edition`.
  A human writes them. No personalisation.
- **The intelligence briefing** — RSS ingested, LLM-classified, ranked per member
  by `get_news_feed`. Lives on Pulse home as a digest preview and in full at
  `app/briefing.tsx`.

Both surface on the Pulse tab. See `docs/AMARI-WORKING-MEMORY.md` for how the
briefing pipeline actually works.

## Getting Started

```bash
npm install
npm run start:dev          # native dev client (not Expo Go)
npm run android:dev
```

Requires a `.env` with the Supabase/Mapbox/Google keys listed in
`docs/RELEASE-WORKFLOW.md`.

## Checks

```bash
npm run verify:release     # eslint + typecheck + expo config validation
npm run test               # jest
npm run verify:security    # static scan for security anti-patterns
```

CI (`.github/workflows/ci.yml`) runs lint → typecheck → verify:security → test
on every pull request and push.

## Documentation

- `AGENTS.md` — agent contract, worktree layout, known defects
- `docs/AMARI-WORKING-MEMORY.md` — system state and how the pipeline works
- `docs/RELEASE-WORKFLOW.md` — builds, store submissions, signing traps
- `docs/SUPABASE-MIGRATION-HISTORY.md` — migration guardrail
- `docs/SECURITY-HARDENING-ROADMAP.md` — security posture
- `docs/eas-update.md` — OTA policy (blocked; ship via store builds)
- `supabase/functions/NEWS-PIPELINE.md` — pipeline runbook and cron SQL

## License

Private — AMARI Group.
