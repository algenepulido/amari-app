# External reviewer authorisation matrix

Prepared 21 September 2026 against commit `d51fe55`.

## How to read this document

Every row states what the code says, and every row is marked as not tested. No test has been run
against any database in producing this matrix. The expected column is derived from reading the
migration that defines the object. The actual column stays empty until a test has run under a
real user token, and the evidence column names the test that filled it.

This is deliberate. A matrix filled in from reading the code would present intent as evidence.
The reason this programme exists is that reading the code is exactly what has been done before
and the invitation pool survived it.

Two rules govern how the tests must be written when they are written. Negative tests are run
with a real user token for the role under test, never with the service role, because the service
role bypasses row level security and proves nothing about a member. Every check must be run once
against a case that must fail, because a check that has only ever passed is not known to work.

The reviewer column describes the design proposed in the access plan. No reviewer role exists
today.

## Grant reality

Grants in this schema come from three places, and reading only the grant statements understates
the surface. A function created without a revoke keeps the Postgres default of execute to public.
There is no blanket revoke and no altered default privileges anywhere in the fifty four
migrations. Of seventy security definer functions, fifty three are named in a revoke statement.
Twelve of the remainder are ordinary callable functions holding the default public grant, and
those are marked below.

## Entry and identity

| Surface | Object | Anonymous | Reviewer | Member | Admin | Expected | Actual | Evidence |
|---|---|---|---|---|---|---|---|---|
| Code validation | `validate_invitation_code` | allowed, explicit grant to anon, `20260504000007:36` | allowed, rate limited | allowed | allowed | valid or invalid only, rate limited per caller | not tested | none |
| Code redemption | `redeem_invitation_code` | denied | not used by reviewers | allowed, `20260521000002:134` | allowed | binds to `auth.uid()` only | not tested | none |
| Reviewer activation | proposed reviewer function | denied | allowed once, Apple identity only | denied | denied | single use, atomic, no tier or admin write | not tested | none |
| Provider inspection | `auth.identities` read in a definer function | denied | server side only | denied | denied | Google or email activation refused | not tested | none |
| Session after expiry | every reviewer-reachable path | denied | denied after expiry | not applicable | not applicable | refusal in the database, not the client | not tested | none |
| Session after revocation | every reviewer-reachable path | denied | denied immediately | not applicable | not applicable | refusal on next server call | not tested | none |

## Member surface reachable at the lowest tier

| Surface | Object | Anonymous | Reviewer | Member | Admin | Expected | Actual | Evidence |
|---|---|---|---|---|---|---|---|---|
| Own profile read | `members` select policy | denied | own row only | own row only, `20260321000003:43` | all rows | self read only | not tested | none |
| Own profile update | `members` update policy | denied | own row only | own row only, `20260321000003:44` | all rows | privileged fields rejected by trigger | not tested | none |
| Pulse editions | `get_pulse_feed`, `get_pulse_edition` | denied | allowed | allowed | allowed | no personalisation claim | not tested | none |
| Briefing feed | `get_news_feed` | denied | allowed over synthetic content | allowed | allowed | own interests only | not tested | none |
| Interests | `set_feed_interests` | denied | own only | own only | own only | deletes only caller rows | not tested | none |
| Saved articles | `toggle_saved_article`, `get_saved_articles` | denied | own only | own only | own only | own rows only | not tested | none |
| Entity follows | `set_entity_follow` | denied | own only | own only | own only | own rows only | not tested | none |
| Events browse | events queries | denied | synthetic events only | allowed | allowed | no production event visible | not tested | none |
| Event registration | `rsvp_to_event`, `cancel_event_rsvp` | denied | synthetic events only | allowed subject to event minimum tier | allowed | own registration only | not tested | none |
| Project map | `map_projects`, `map_states`, `map_countries` | **allowed today, default public grant, `20260326000001:159`** | synthetic only | allowed | allowed | should require a member, currently does not | not tested | none |
| Issue report | `report_issue` | denied | allowed, sink destination | allowed | allowed | must not page real administrators | not tested | none |
| Account deletion | `request_account_deletion` | denied | own only | own only | own only | own record only | not tested | none |

## Surfaces a reviewer must not reach

| Surface | Object | Expected for reviewer | Actual | Evidence |
|---|---|---|---|---|
| Any administrative route | `app/admin/*` | denied by absence of an `admin_roles` row | not tested | none |
| Tier change | `change_member_tier` | denied, requires `is_admin()`, `20260321000003:172` | not tested | none |
| Member status change | `admin_set_member_status` | denied | not tested | none |
| Create invitation codes | `admin_create_invitation_code` | denied | not tested | none |
| Monthly invitation codes | `create_monthly_invite` | denied, requires platinum or laureate | not tested | none |
| Door check-in | `verify_barcode`, `get_event_checkin_stats` | denied | not tested | none |
| Publish content | `app/admin/pulse.tsx` paths | denied | not tested | none |
| Moderate projects | `review_aligned_tile`, `admin_set_project_status` | denied | not tested | none |
| Issue queue | `set_issue_status` | denied | not tested | none |
| Another member's contact details | `get_aligned_tile_contact_details` | denied at the lowest tier, and no real member exists in the environment | not tested | none |
| Aligned surface | `app/(tabs)/aligned/*` | denied at the lowest tier, requirement is level three | not tested | none |
| Rate limit table | `check_rate_limit` | denied, currently holds the default public grant | not tested | none |
| Arbitrary user binding | `redeem_invitation_code` with another user identifier | denied, the reviewer path must compare `auth.uid()` | not tested | none |

## The tests that must fill the actual column

Each corresponds to a requirement in the brief. Every one is a test that must fail for the
subject under test, except where stated.

- A reviewer code can be redeemed once, and the same code cannot be redeemed again.
- An expired code cannot be redeemed, and a revoked code cannot be redeemed.
- Two concurrent redemptions of one code produce exactly one success.
- A Google identity and an email identity cannot activate a reviewer slot.
- A reviewer cannot obtain an `admin_roles` row by any path, including the invitation path.
- A reviewer cannot raise their own tier.
- A reviewer can read the content the design permits.
- A reviewer cannot read the content the design forbids.
- A reviewer cannot read another user's sensitive fields.
- An anonymous caller cannot use any reviewer function.
- An expired reviewer is refused by the database, not merely hidden by the client.
- A revoked reviewer is refused on the next server call.
- A reviewer cannot invoke the restricted security definer functions listed above.
- Rate limiting refuses the caller at the configured threshold and the refusal is observable.
- Every reviewer write lands only on the reviewer's own record or on synthetic data.
- No production notification or email is emitted by any reviewer action.
- No log line contains a token, a secret, an authentication header or an Apple identity token.

## Independent verification already carried out

The inventory behind this matrix was produced twice, once by an inspection worker reading the
migrations and once by a separate parse of the same files. The worker named sixty nine of the
seventy security definer functions and invented none. The parse was itself wrong twice and was
corrected: it first treated a missing grant statement as meaning a function was unreachable,
which is false because the default is public, and its revoke matcher then missed revokes written
without a parameter list. The numbers in this document are the corrected ones.
