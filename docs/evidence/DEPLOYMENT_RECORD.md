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
| Executed by | Claude Code, direct psql from the terminal, no browser, no clipboard |
| Deployment timestamp, UTC | 2026-09-22T01:15:06Z start, 01:15:09Z commit |
| Hash verified immediately before execution | yes, 38e3142e... and 27,290 bytes |
| Connection | session pooler, TLSv1.3, AES-256-GCM, verified by \conninfo |
| One `begin;` and one `commit;` | verified mechanically, one of each |
| Reissue targets captured beforehand | 9, asserted server-side |
| Supabase RLS warning | not applicable, psql path bypasses the dashboard linter entirely |
| Notices returned | map smoke tests 3/1/1 rows; containment complete, 1216 expired, 9 created, 23 members and 4 administrators unchanged |

## Before and after

| Control | Before | Required after | Actual after |
|---|---|---|---|
| Valid unused invitations | 1,216 | 9 | 9 PASS |
| Valid unused admin-capable | 9 | 0 | 0 PASS |
| Valid unused bootstrap | 1,209 | 0 | 0 PASS |
| Valid unused predictable legacy | 1,209 | 0 | 0 PASS |
| Valid unused weak suffix | 1,216 | 0 | 0 PASS |
| Valid unused replacements | 0 | 9 | 9 PASS |
| Replacements failing requirements | n/a | 0 | 0 PASS |
| Members | 23 | 23 | 23 PASS |
| Administrator roles | 4 | 4 | 4 PASS |
| Role composition | 1 owner, 3 admins | unchanged | 1 owner, 3 admins PASS |
| Redeemed invitations | 24 | 24 | 24 PASS |
| Backup rows for rollback | 0 | 1,216 | 1,216 PASS |

## Authorisation controls after deployment

| Control | Required | Actual |
|---|---|---|
| `anon` execute on `redeem_invitation_code` | false | false PASS |
| `anon` execute on `map_projects`, `map_states`, `map_countries` | false | false PASS |
| `anon` execute on `check_rate_limit`, `cleanup_rate_limits` | false | false PASS |
| `authenticated` execute on `cleanup_rate_limits` | false | false PASS |
| `anon` execute on `validate_invitation_code` | true, unchanged | true PASS |
| PUBLIC execute on any of the above | false | false PASS |

## Grids preserved

| Grid | Path |
|---|---|
| Before, statement one, FRESH, captured immediately before the run | `docs/evidence/before-20260922T011456Z-statement-one.csv` |
| Earlier baseline, 08:01, retained for reference only, not the paired before grid | `docs/evidence/before-20260922-080109-statement-one.csv` |
| After, statement one | `docs/evidence/after-20260922T011536Z-statement-one.csv` |
| Admin reconciliation after | `docs/evidence/after-20260922T011536Z-admin-reconciliation.csv` |

## Physical iPhone checks

Run after database verification passes and before any code is distributed.

| Check | Result |
|---|---|
| Onboarding with a 48 character replacement succeeds at the intended tier | |
| Aligned map loads for a gold or above member | |
| Administrator panels load and a tier change works | |
| Member and silver cannot reach the Aligned map | |

## Anomalies

Three, none affecting the outcome.

**A transient authentication failure immediately before success.** The first connection attempt failed
on password authentication and the next, seconds later with identical settings, succeeded. Cause was a
race: the credential file was being rewritten by the setup window while the first attempt fired. Proven
benign by three consecutive independent connections afterwards, all successful. No deployment action was
taken until that was resolved.

**A false drift alarm on the reissue capture.** The capture appeared to return ten targets rather than
nine, which would have been a stop condition. Cause was a defect in the capture command, not the data:
psql's row-count footer was not suppressed and was counted as a data row. The server was then asked to
assert the count directly and returned exactly nine. No production state had changed.

**Schema-wide privilege reduction beyond the named objects.** Definer functions executable by anon fell
from 16 to 11, by PUBLIC from 15 to 10, those without a fixed search_path from 8 to 5, and anon-callable
functions with no auth.uid() check from 13 to 8. This is the intended consequence of the named revokes
and the three map function rewrites, not additional remediation. No object outside the approved list was
altered.

## Distribution

Not before every check above passes.

| Field | Value |
|---|---|
| Codes distributed | _no, or the date_ |
| Channel used | |
| Recipients confirmed receipt | |
