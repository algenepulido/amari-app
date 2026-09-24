# External reviewer access plan

Prepared 21 September 2026 against commit `d51fe55` on `docs/release-1.2.5-final-evidence`,
which is the current 1.2.5 release line. Note that `master` is far behind at version 1.0.0
and does not describe the shipped application.

## Status

Phase zero inspection is complete. No implementation has begun, no database object has been
created or altered, and no reviewer credential exists. The work stops at the phase one
environment decision because three of the stop conditions set out in the brief are met. Those
conditions are named under "Why this plan stops here".

Nothing in this document has been executed against the production database. Every statement
about the live data population is marked as unverified, because verifying it requires a query
that has not been authorised.

## How the inspection was carried out

Six independent read-only inspection workers examined disjoint areas of the repository:
environment and secret hygiene, authentication and session, invitation and entry, the client
surface reachable by the lowest tier, database authorisation, and test data with outbound
effects. Each was fenced to named paths, forbidden from writing, forbidden from any network or
database call, and required to attach file and line evidence to every claim.

Their reports were then checked rather than accepted. An independent parse of all fifty four
migrations produced a separate inventory of function definitions, security attributes and
grants, and that inventory was diffed against the database worker's report. The worker named
sixty nine of the seventy security definer functions, omitted one, and invented none. It found
three of the four findings that had been established by hand and missed the fourth, which the
invitation worker found in its own lane. The checking also corrected the orchestrator's own
parse twice, which is recorded under "Corrections made during verification".

## The application as it stands

### Environment

There is one Supabase project. The development, preview and production build profiles in
`eas.json` all carry the same project URL and the same anonymous key, at lines 13, 31 and 50.
There is no staging project, no second environment file, and no runtime switch that selects a
different backend. `lib/supabase.ts:6` and `lib/supabase.ts:7` read the two public environment
variables and pass them straight to `createClient`.

### Authentication

Apple sign-in uses `expo-apple-authentication` with a hashed nonce and calls
`supabase.auth.signInWithIdToken` with `provider: 'apple'` at `lib/appleAuth.ts:35`. Google
sign-in and email one-time codes also exist and can both create accounts. Supabase therefore
records the provider, but nothing in the application reads it afterwards. A search of every
migration and every client path found no reference to `auth.identities`, to a provider claim,
or to any provider comparison. `providers/AuthProvider.tsx:45` reads only the tier and admin
claims.

### Entry through invitation codes

Codes are stored as a SHA-256 hash in `invitation_codes.code_hash`, and the plaintext `code`
column from the original schema was never dropped. Validation runs through
`validate_invitation_code`, which is security definer and granted to the anonymous role.
Redemption runs through `redeem_invitation_code`, which is security definer, granted to the
authenticated role, and creates the member row, the admin role where the invitation carries
one, and the authentication metadata.

### Privilege model

Membership tier is an enum with five values, member, silver, gold, platinum and laureate.
Administrative status is a row in `admin_roles`, and `public.is_admin()` at
`supabase/migrations/20260321000003_authority_hardening_v2.sql:28` reads that table. The custom
access token hook mints the tier and admin claims from the same tables at token issue, so the
claim follows the database rather than leading it. The March authority hardening is sound where
it applies: `change_member_tier` requires admin, members row level security is self-read only,
and a trigger rejects direct updates to privileged member fields.

### Client surface

The lowest tier reaches Pulse, the briefing, events, and the profile. Aligned requires level
three, which is gold, although the layout and the tab bar both call level three Platinum.
Corridor is hidden from everyone because its effective requirement in `lib/theme.ts` is
ninety nine, while `lib/constants.ts` still says two. Discover and Network are blank stubs. The
root guard at `app/_layout.tsx:65` requires a session and an onboarded member row, and although
it reads the member status it does not act on it, so a suspended account is not rejected by the
client. Whether the server rejects it is unverified.

### Database authorisation

Seventy functions are security definer. Fifty three are named in at least one revoke statement.
There is no blanket revoke and no altered default privileges anywhere in the schema, so every
function that is never revoked keeps the Postgres default of execute to public. Twelve security
definer functions are in that position and are callable rather than trigger functions. The
consequential ones are `check_rate_limit`, which lets any caller insert arbitrary rows into the
rate limit table, and the three map functions, which return project name, description, category,
creator first name, image, link and coordinates for any bounding box without any membership
check at all.

### Outbound effects

An ordinary member can cause a push notification to another member by requesting project
contact, and can cause a push notification to every administrator by reporting an issue. Both
run through edge functions. No email provider, SMTP call or email edge function exists in the
repository. Neither PostHog nor Sentry is installed as a dependency; both are guarded shims, so
native crash visibility is absent.

### Test data

`supabase/seed.sql` is headed as development test data and seeds four invitation codes, one
Pulse edition, five events and four corridor opportunities. It creates no members and no
projects. One of its four codes grants laureate tier with administrative rights. Whether that
file has ever been applied to the production project is unverified.

## The environment decision

### Option A, a dedicated reviewer environment

This is the only option that satisfies the brief as written. It requires a new Supabase project,
a separate authentication population, the full migration history applied to it, a synthetic data
set, a separate environment configuration, and an iOS build pointing only at it. The repository
supports this cleanly, because the client reads its backend from two environment variables and
the build profiles already exist. The cost is a new project that has not been approved, and the
work is substantial rather than trivial. An estimate is given below.

### Option B, an existing safe staging environment

Not available. No staging environment exists. The preview and development profiles are names
attached to the production database.

### Option C, production

Forbidden by the brief without explicit approval, and independently inadvisable given the
findings in the threat model. Reviewer isolation inside the production database would rest on
the same authorisation layer that currently contains a path to administrative control.

## Why this plan stops here

Three stop conditions from the brief are met.

Privileged credentials appear committed in git. The current bootstrap invitation pool is
inserted from literal, predictable values at
`supabase/migrations/20260323000001_membership_invites_and_moderation.sql:962`, and twelve of
those codes carry an administrative grant at laureate tier with a one year expiry set on
23 March 2026. Separately, a real production invitation code and a named person's email address
are committed in plain text in `scripts/verify-mobile-flows.mjs:37` and in
`docs/TINASHE-ANDROID-TEST-SCRIPT.md`.

An existing vulnerability would allow reviewer isolation to be bypassed. The chain is set out in
the threat model. In summary, the validation function is callable anonymously with no rate limit
since `20260504000007`, the redemption function accepts a caller-supplied user identifier
without comparing it to `auth.uid()`, and redemption of an administrative invitation writes a row
into `admin_roles`, which is the table every administrative check reads.

Creating a separate reviewer environment requires infrastructure that has not been approved.

## Corrections made during verification

Two errors in the orchestrator's own parse were found and fixed before any number in this
document was reported. The first was treating the absence of a grant statement as meaning a
function was unreachable, when the Postgres default is execute to public. The second was a
revoke matcher that required a parameter list and therefore missed
`REVOKE EXECUTE ON FUNCTION custom_access_token_hook`, which is written without one. Both are
recorded because the corrected numbers are the ones used above.

## The reviewer design, if approved

The design below is what would be built under option A. It is recorded so the decision can be
made against something concrete, not as work in progress.

### Reviewer slot model

Eight independent slots, `REVIEWER-01` through `REVIEWER-08`, each bound to exactly one
authenticated identity on first redemption. A reviewer slots table holds the slot name, the
code hash, the bound user identifier, the activation time, both expiry times, a revoked flag and
a last seen time. No plaintext code is stored.

### Code generation and handling

Two hundred and fifty six bits of entropy per code from a cryptographic source, stored only as a
hash. Plaintext written once to `secure-output/external-reviewer-codes.txt`, which is added to
`.gitignore` before any code is generated, with the file permissions restricted to the current
user. The file carries the slot, the code, the creation time and the hard expiry, and nothing
else. Codes are never printed to terminal output.

### Apple-only activation

The activation function reads the caller's identity from `auth.uid()` and confirms an Apple
identity exists for that user in `auth.identities`, rather than trusting any value the client
sends. This is the one part of the design that rests on an assumption which has not been proven
in this repository, because no existing function reads `auth.identities`. It must be proven by a
test that signs in with Google and is refused, before it is relied upon. A platform check in
React Native is not a security boundary and is not used as one.

### Atomicity

Redemption selects the slot row `for update`, verifies it is unused, unexpired and unrevoked,
binds it, and marks it consumed in the same transaction. A second concurrent redemption of the
same code fails. This mirrors the locking already used in `redeem_invitation_code`, which does
take `for update skip locked`.

### Expiry and revocation

Seventy two hours after first activation, or seven days after code creation, whichever falls
first. Expiry is evaluated inside the database on every reviewer-reachable path, not in the
client and not only at sign-in, so a cached session does not outlive it. Revocation sets the
flag and takes effect on the next server call.

### Privilege floor

The reviewer is created at the lowest tier and is never granted an administrative role. The
activation path cannot set a tier, cannot write to `admin_roles`, and cannot write to
authentication metadata. This is a deliberate departure from the shape of the existing
redemption function, which can do all three.

### Synthetic data

Between eight and twelve fictional members, fictional companies and profiles, several briefing
cards, two or three events with at least one past and one upcoming, several projects with map
locations that carry nothing sensitive, journal entries, interests and entities. Every record
authored from scratch. No production record is copied, and no production record is anonymised,
because anonymisation of a real record is not synthesis.

### Rate limiting

Server enforced, keyed on the authenticated subject where one exists and on a server-observed
value otherwise, never on a caller-supplied address. Applied to code validation, code
redemption, the authentication-adjacent reviewer paths, expensive functions and any upload. The
validation path must not answer valid or invalid without limit, which is the defect the current
production function has.

### Audit

Slot, user identifier, timestamp, event type, and outcome for sign-in, redemption, denial,
expiry, revocation, security-sensitive calls and significant writes. No token, no secret, no
authentication header and no Apple identity token is ever written to the log. A single query
reports activity by slot.

### Outbound sinks

In an isolated environment the push and email destinations are test sinks. Reviewer analytics
carry a cohort tag so they can be excluded from ordinary engagement metrics.

## Exact objects that would change

No file in this list has been changed.

| Object | Change |
|---|---|
| `.gitignore` | add `secure-output/` |
| new migration | reviewer slots table, activation function, expiry predicate, audit table, rate limit table and function, all grants explicit |
| new migration | reviewer visibility policies over synthetic content |
| `scripts/seed-reviewer-environment.ts` | synthetic data seed, reviewer environment only, refuses to run against the production project reference |
| `scripts/revoke-external-reviewers.ts` | revocation and kill switch, dry run by default, `--confirm` required to act |
| `supabase/tests/` | the negative tests listed in the brief, run under real user tokens |
| `eas.json` | a reviewer profile pointing at the reviewer project only |
| `docs/EXTERNAL_REVIEWER_OPERATOR_GUIDE.md` | written once the environment exists |

No change to any existing function, policy or table in production is proposed by this plan. The
separate remediation of the findings in the threat model is a different piece of work and should
not be folded into the reviewer programme.

## Rollback

In an isolated environment, rollback is the revocation script followed by deletion of the
reviewer project. Nothing in production is touched, so there is nothing in production to roll
back. That property is the main argument for option A over option C.

## Reviewer journeys that would work

Install the build, enter the reviewer code, sign in with Apple, complete onboarding, choose
interests, read Pulse and the briefing, browse the news feed, browse events, register for a
synthetic event, browse the projects and the map at the lowest tier, edit their own synthetic
profile, set notification preferences, sign out and sign back in. Every write either touches the
reviewer's own record or synthetic reviewer-environment data.

Aligned would remain out of reach at the lowest tier, because its requirement is level three.
That is a genuine limit on what a reviewer would see and should be stated to them rather than
worked around by raising their tier.

## iOS distribution

No workflow in the repository builds or submits an iOS binary. The EAS Build workflow is Android
only, at `.github/workflows/eas-build.yml:14`. The production submit profile is configured for
App Store Connect with an application identifier and an Apple account email committed at
`eas.json:59`. A reviewer build would therefore be produced by running EAS locally or by adding
an iOS workflow, and distributed through TestFlight internal or external testing. Eight external
testers fit comfortably within internal testing limits only if they are added to the App Store
Connect team, which is usually not appropriate for untrusted reviewers, so external testing with
a review pass is the realistic route. That is an Apple account consideration and is flagged
under the brief's stop condition about material changes to the Apple setup.

## What this plan deliberately does not include

The operator guide is not written, because it would document the operation of an environment
that does not exist. The authorisation matrix is included but every actual result column is
marked as not tested, because no test has been run against any database. A matrix filled in from
reading the code would be a statement of intent presented as evidence, and the point of the
matrix is to be evidence.
