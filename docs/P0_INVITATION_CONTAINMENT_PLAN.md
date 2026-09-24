# P0 invitation containment plan, revision 2

Prepared 21 September 2026. Nothing in this plan has been applied. Production is unchanged.

The migration is `supabase/migrations/20260921000001_p0_invitation_containment.sql`. The rollback
is `scripts/rollback-p0-invitation-containment.sql`. The regression suite is
`supabase/verification/p0/p0_invitation_containment.test.sql`.

## What the live evidence established

Verified live on 21 September 2026 at 11:57 UTC, with grids under `docs/evidence/`.

Nine admin-capable invitations are valid and unused, eight of them in the predictable published
bootstrap format. `redeem_invitation_code` is executable by PUBLIC and anon and does not reference
`auth.uid()`. `check_rate_limit` and `cleanup_rate_limits` are executable by PUBLIC and anon. The
three map functions are executable by anon and set no search path. All four existing administrators
arrived through the historical bootstrap path, which is the expected shape rather than evidence of
intrusion.

One further thing was established before any of this was designed. The body of every function in
scope is byte-identical between production and the repository, once line endings are normalised.
That was checked by comparing `md5(prosrc)` from the live catalogue against the hash of the last
definition in the migrations. It matters because it means the repository source can be reasoned
from, rather than merely hoped about.

## Phase 1. Object by object

### `redeem_invitation_code(text, uuid, text, text, text, text)`

- Current live grant: PUBLIC true, anon true, authenticated true, service_role true.
- Internal authorisation checks: none.
- References `auth.uid()`: no.
- Caller-supplied user identifier: yes, `p_user_id`, used directly for the member insert, the
  `admin_roles` insert and the `auth.users` metadata write.
- Current client call path: `providers/AuthProvider.tsx:199`, inside an effect guarded on an
  established session, passing `state.user.id`. The code is held in secure storage during the
  pre-authentication flow and redeemed only after sign-in. There is no other call site.
- Effect of revoking anon and PUBLIC: none on the shipped client, including builds already in the
  field, because redemption never happens before authentication.
- Proposed safe grant: authenticated only.
- Rollback: section 2 of the rollback script restores the grants; section 5 restores the previous
  body.
- Regression tests required: anonymous redemption refused, redemption for another identity refused,
  fail closed when there is no authenticated caller, ordinary onboarding still succeeds, the member
  row is created under the caller rather than under the supplied identifier.

### `validate_invitation_code(text)`

- Current live grant: PUBLIC false, anon true, authenticated true, service_role true.
- Internal authorisation checks: none, by design.
- References `auth.uid()`: no.
- Caller-supplied user identifier: none.
- Current client call path: `app/(auth)/invite.tsx:54` and `components/v2/Onboarding.tsx:318`, both
  before sign-in.
- Effect of revoking anon: it would break onboarding for every new member. Not proposed.
- Proposed safe grant: unchanged. This is the one anonymous capability the product genuinely needs.
- Rollback: not applicable, nothing changes.
- Regression tests required: an anonymous caller can still validate.

### `check_rate_limit(text, text, integer, integer)`

- Current live grant: PUBLIC true, anon true, authenticated true, service_role true.
- Internal authorisation checks: none. Sets no search path.
- References `auth.uid()`: no.
- Caller-supplied user identifier: yes, `p_ip`, which is why it cannot be trusted as an identity.
- Current client call path: none anywhere in the application.
- Effect of revoking anon and PUBLIC: none. A SECURITY DEFINER function that calls it executes as
  its owner, so server-side use is unaffected by the caller's own privileges.
- Proposed safe grant: service_role only.
- Rollback: section 2.
- Regression tests required: an anonymous caller cannot write rate limit rows directly.

### `cleanup_rate_limits()`

- Current live grant: PUBLIC true, anon true, authenticated true, service_role true. Not SECURITY
  DEFINER.
- Internal authorisation checks: none.
- Current client call path: none anywhere in the application.
- Effect of revoking anon and PUBLIC: none.
- Proposed safe grant: service_role only.
- Correction to revision 1. That revision called this a precondition for rate limiting, on the
  reasoning that an anonymous caller could clear its own throttle. The live dependency analysis
  shows `public.rate_limits` already has row level security enabled with no policy, which denies
  every application role irrespective of table grants, so the delete would have affected zero rows.
  Revoking it is defence in depth, not a precondition.
- Rollback: section 2.
- Regression tests required: an anonymous caller cannot clear the rate limit table.

### `map_projects`, `map_states`, `map_countries`

- Current live grant: PUBLIC true, anon true, authenticated true, service_role true. None sets a
  search path, and all three are SECURITY DEFINER.
- Internal authorisation checks: none.
- What they return: project identifier, name, description, category, creator first name, display
  label, image URL, external link and coordinates. Coordinates are coarsened to a region centroid
  at insert time, so they are approximate, but the records are member-facing content.
- Current client call path: `hooks/useMapData.ts:26`, `:45` and `:69`, consumed only by
  `app/(tabs)/aligned/index.tsx` and `components/aligned/ProjectMap.tsx`. No edge function calls
  them; `refresh-map-data` calls `refresh_map_cache`, which is untouched.
- Proposed: authenticated only as a grant, **and** an authorisation check inside each function.
  Requiring authentication alone is not sufficient, because a lower-tier member could call the RPC
  directly while the client merely hides the tab.

**The business rule, and an ambiguity I am not resolving silently.** The client gate reads
`TAB_VISIBILITY.aligned = 3` against `TIER_LEVELS`, where gold is 3. So the rule the application
actually enforces today is gold and above. The copy on the same screen says "Available from
Platinum membership". The constant and the sentence disagree, and they have disagreed since the
gold tier was introduced. This migration reproduces what is enforced, gold and above, so that
nothing which works today stops working. If the intended rule is platinum, that is a one-word
change in the guard plus a copy fix, and it is a product decision rather than a security one.

- The guard reads `members.tier` directly rather than calling `get_member_tier()`, because that
  helper falls back to a JWT claim. For an authorisation gate the row is the authority.
- Administrators are admitted regardless of tier.
- Search path fixed to `public, extensions`, proven by an in-migration smoke test that aborts the
  transaction if PostGIS cannot be resolved or a rewritten body is wrong.

### `is_admin()`, `is_active_member()`, `get_member_tier()`

- Current live grant: PUBLIC true, anon true.
- All three reference `auth.uid()`, so an anonymous caller learns only that it is nobody.
- Proposed change: none. They are on the allow-list pass, not in containment.

## Phase 2A. Admin-capable invitations

Every valid unused invitation that can grant administrative rights is expired by setting
`expires_at` to now. No row is deleted, no redeemed invitation is altered, and the prior expiry of
each affected row is written to a backup table first so that rollback restores exact values rather
than an approximation.

The migration then asserts the objective and raises if it is not met, so a partial result cannot
commit.

Impact is nil for any individual. The baseline query established that **none** of the nine is
addressed to a named recipient, so no person is waiting on one of these codes.

## Phase 2B. The predictable pool is now retired in full

Revision 2 takes the stronger line. The migration expires every valid unused invitation that is
admin-capable in any format, or issued from the bootstrap source, or whose code matches the
published predictable pattern. Three post-conditions are asserted inside the transaction and a
partial result cannot commit.

Exact impact, measured live rather than estimated. The predicate matches **1,210** rows. Three of
them are addressed to a named person. **Six** valid unused invitations survive, and all six are
from the controlled admin path and addressed to named recipients. The one admin-capable code that
is not in the predictable format is also caught, by the admin-capable clause.

The three named recipients need replacements rather than a preserved legacy credential. Reissuing
is possible with what already exists: `admin_create_invitation_code` generates a random suffix and
is reachable from Admin then Codes in the app. No product change is required. The list of who they
are is produced by `secure-output/pending-reissue-list.sql`, which is gitignored because its output
contains names and email addresses, and which must be run **before** the migration, because
afterwards those rows are expired and the predicate no longer matches them.

The residual is the one you accepted: somebody informally handed a static code will find it no
longer works, and we cannot know who that is. Against a pool that includes silver, platinum and
laureate grants, that is the right trade.

## Phase 2C. Redemption

The condition in the brief is met: the user is authenticated before redemption, so anonymous access
is removed rather than preserved. The function now derives identity from `auth.uid()`, refuses any
caller-supplied identifier that does not match it, and fails closed when there is no authenticated
caller. The signature is deliberately unchanged so that clients already in the field keep working.

Not changed, and recorded as the first follow-up: the Apple private relay exception at the email
check tests the shape of a caller-supplied string rather than the authentication provider. With
admin-capable codes expired, the worst it now permits is redeeming an ordinary code addressed to
somebody else. That should be fixed, and it is not containment.

## Phase 3 amendment. Live dependency analysis for the rate limit functions

Run against production before the revokes were written, not inferred from the repository.

| Question | Answer |
|---|---|
| Other database functions referencing either name | none |
| Trigger functions referencing either name | none |
| Views or rules referencing them | none |
| Edge functions referencing them | none; `refresh-map-data` calls `refresh_map_cache`, untouched |
| Owner of both functions | `postgres` |
| Direct privileges on `public.rate_limits` | anon has select, insert and delete; authenticated has select and delete |
| Row level security on `public.rate_limits` | enabled, zero policies, not forced |

Two conclusions follow. Nothing internal calls either function, so revoking execute breaks no
server-side path. And the alarming-looking table privileges are inert, because row level security
with no policy denies every non-owner role. The migration removes those redundant grants anyway, so
that a privilege which looks live and is not cannot mislead somebody later. That block is clearly
marked and can be struck if you want the change narrower.

A consequence worth recording: because no function calls `check_rate_limit` any more, restoring
rate limiting later means adding the call back, not merely re-granting it.

## Phase 2D and 2E. Rate limiting

`cleanup_rate_limits` and `check_rate_limit` become internal. That is a precondition for any rate
limit to be meaningful.

Restoring a rate limit inside `validate_invitation_code` is **not** in this migration, and the
honest reason is that a per-caller key for an unauthenticated caller is not a solved problem here.
There is no `auth.uid()` before sign-in. `inet_client_addr()` returns the connection pooler rather
than the caller. A forwarded-for header is partly caller-controlled, and the brief rightly says not
to trust a caller-supplied address as the authority. The previous implementation keyed every
anonymous caller into one shared bucket, which is why it was removed rather than fixed in May.

The strongest containment for the oracle is therefore not rate limiting. It is removing what the
oracle is worth finding, which is phases 2A and 2B. Rate limiting should come back as defence in
depth once a trustworthy caller key is chosen, and that choice should be made deliberately rather
than smuggled into an emergency change.

## Phase 4. Default function privileges

The migration sets `alter default privileges for role postgres in schema public revoke execute on
functions from public`. This affects functions created from that point onward and touches nothing
that exists. `create or replace` preserves an existing function's privileges, so later edits do not
silently undo it.

Two caveats worth knowing. Default privileges are recorded per creating role, so if migrations are
ever applied as a role other than `postgres` the default will not apply to those functions, and the
allow-list pass below is what catches that. And the fifteen functions that currently hold a PUBLIC
grant are untouched here on purpose, because a mass revoke would break the live application.

The long-term model to converge on:

- PUBLIC: nothing, ever, by default.
- anon: an explicitly named list, currently just `validate_invitation_code`.
- authenticated: an explicitly named list.
- service_role and internal: operational functions only.

Retiring the existing PUBLIC grants belongs in a separate reviewed change, one function at a time,
each with a test.

## Phase 5. Plaintext invitation codes

Not touched here. The plaintext `code` column is populated on all 2,053 rows, and the emergency
change deletes and rewrites nothing.

The replacement design, for a later migration once it can be proven: codes generated from a
cryptographic source with at least 192 bits of entropy, stored only as a hash, looked up by hash,
single use, explicit expiry, redemption atomic under concurrency, and no privilege encoded in a
guessable pattern. Administrative rights should not be grantable by an invitation code at all;
elevation should be an explicit administrative action against a named account.

Existing plaintext values should be nulled only after the replacement path is proven in production,
and never as part of the same change that introduces it.

## Phase 6. Tests

`supabase/verification/p0/p0_invitation_containment.test.sql` covers eighteen assertions under real
roles and real JWT subjects. The service role is never used to demonstrate a client-side property.

What has already been executed, and what has not. The migration, the rollback and the behavioural
assertions were run end to end against a disposable PostgreSQL 16 instance loaded with a fixture
reproducing every object the migration touches. That validates syntax, control flow, grant
outcomes and the identity binding. It is not a full integration run against a PostGIS-enabled clone
of production, and it is not claimed to be. The pgTAP suite is the integration proof and runs in CI
through `supabase start`.

One fixture defect was found and fixed during that run: the first attempt set the test identity
with a transaction-scoped `set_config` under psql autocommit, so the identity was never present and
four tests returned `not_authenticated`. Each of those would have looked like a refusal for the
right reason. They were re-run with a session-scoped setting and then produced the specific,
different refusals the controls are supposed to produce.

## Phase 7. Migration safety

### Pre-change counts, captured live

| Measure | Value |
|---|---|
| Admin-capable valid unused | 9 |
| Of those, addressed to a named person | 0 |
| Bootstrap valid unused | 1,209 |
| Of those, addressed to a named person | 3 |
| Admin-source valid unused | 7 |
| Of those, addressed to a named person | 6 |
| Members | 23 |
| `admin_roles` rows | 4 |
| Redeemed invitations | 24 |

### Pre-change grants, captured live

| Function | PUBLIC | anon | authenticated | service_role |
|---|---|---|---|---|
| `redeem_invitation_code` | true | true | true | true |
| `validate_invitation_code` | false | true | true | true |
| `check_rate_limit` | true | true | true | true |
| `cleanup_rate_limits` | true | true | true | true |
| `map_projects` | true | true | true | true |
| `map_states` | true | true | true | true |
| `map_countries` | true | true | true | true |

### Expected downtime

None. Every statement is a metadata change, a grant change, or an update to at most nine rows. The
transaction takes locks on `invitation_codes` rows and on the affected function definitions for the
duration, which is milliseconds. No table is rewritten and no index is rebuilt.

### Client flows affected

| Flow | Effect |
|---|---|
| Enter a code before signing in | None. Validation is unchanged. |
| Sign in and redeem | None. Already authenticated, already passes its own identifier. |
| Aligned map | None for a signed-in member. An anonymous caller loses access it should never have had. |
| Admin panels | None. |
| Everything else | None. No other object is touched. |

### What is tested immediately afterwards

Re-run the live verification script and confirm `admin_capable_valid_unused` is zero and the grant
rows show anon false for redemption, the rate limit pair and the three map functions. Then, on a
device, complete one ordinary onboarding end to end with a member-tier code, and open the Aligned
map as a signed-in member.

## Residual risk after this change

The predictable member-tier pool remains until phase 2B is decided, so a stranger could still obtain
ordinary member access. The Apple relay email bypass remains. Validation remains an unrated oracle,
worth much less than before but not nothing. Aligned tier gating remains client-side. Fifteen
functions still hold a PUBLIC grant and need the allow-list pass. Plaintext codes remain stored.

None of those is a path to administrative control, which is what this change is for.
