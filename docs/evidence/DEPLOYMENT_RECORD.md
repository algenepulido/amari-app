# P0 containment deployment record

To be completed immediately after the manual deployment. Counts, object names and grant booleans
only. No invitation codes, no recipient names, no email addresses, no tokens.

## Approved artefacts

| Item | Value |
|---|---|
| Migration | `supabase/migrations/20260921000001_p0_invitation_containment.sql` |
| Migration SHA-256, LF | `38e3142ef20602ef82fb9b2e365b932bf0e6481399f58e876a3a2634e0e1bd39` |
| Migration length | 27,290 |
| Rollback | `scripts/rollback-p0-invitation-containment.sql` |
| Rollback SHA-256, LF | `23b84826d204acf187630bc2dfb5ca739e52e29e3f1181ced227d3d62b80a5a0` |
| Approved at commit | `5c3511b` |

## Execution

| Field | Value |
|---|---|
| Executed by | Jeremy, manually, fresh SQL Editor session |
| Deployment timestamp, UTC | _to fill_ |
| Hash verified before paste | _yes or no_ |
| Length verified before paste | _yes or no_ |
| One `begin;` and one `commit;` confirmed visually | _yes or no_ |
| Reissue targets captured beforehand | _count, must be nine_ |
| Supabase RLS warning shown | _yes or no, and which option chosen_ |
| Notices returned | _paste the four notices_ |

## Before and after

| Control | Before | Required after | Actual after |
|---|---|---|---|
| Valid unused invitations | 1,216 | 9 | |
| Valid unused admin-capable | 9 | 0 | |
| Valid unused bootstrap | 1,209 | 0 | |
| Valid unused predictable legacy | 1,209 | 0 | |
| Valid unused weak suffix | 1,216 | 0 | |
| Valid unused replacements | 0 | 9 | |
| Replacements failing requirements | n/a | 0 | |
| Members | 23 | 23 | |
| Administrator roles | 4 | 4 | |
| Role composition | 1 owner, 3 admins | unchanged | |
| Redeemed invitations | 24 | 24 | |
| Backup rows for rollback | 0 | 1,216 | |

## Authorisation controls after deployment

| Control | Required | Actual |
|---|---|---|
| `anon` execute on `redeem_invitation_code` | false | |
| `anon` execute on `map_projects`, `map_states`, `map_countries` | false | |
| `anon` execute on `check_rate_limit`, `cleanup_rate_limits` | false | |
| `authenticated` execute on `cleanup_rate_limits` | false | |
| `anon` execute on `validate_invitation_code` | true, unchanged | |
| PUBLIC execute on any of the above | false | |

## Grids preserved

| Grid | Path |
|---|---|
| Before, statement one | `docs/evidence/before-20260922-080109-statement-one.csv` |
| After, statement one | _to add_ |
| Admin reconciliation after | _to add_ |

## Physical iPhone checks

Run after database verification passes and before any code is distributed.

| Check | Result |
|---|---|
| Onboarding with a 48 character replacement succeeds at the intended tier | |
| Aligned map loads for a gold or above member | |
| Administrator panels load and a tier change works | |
| Member and silver cannot reach the Aligned map | |

## Anomalies

_Record anything unexpected, including anything that looked fine but was not asked for._

## Distribution

Not before every check above passes.

| Field | Value |
|---|---|
| Codes distributed | _no, or the date_ |
| Channel used | |
| Recipients confirmed receipt | |
