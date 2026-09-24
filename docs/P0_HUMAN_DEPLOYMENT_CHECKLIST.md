# P0 containment, human deployment checklist

For Jeremy to run by hand. Automated browser control must not be used to press Run.

## Why this is done by hand

The previous attempt through browser automation hit two problems. Another process on the machine
took the clipboard mid-sequence and a stray string was pasted into the production SQL editor and
executed, returning a syntax error. Then an attempt to bypass the clipboard by setting the editor
content programmatically left the editor displaying one query while the application submitted
another. Neither is acceptable for a production migration, so this is a manual procedure.

## Pinned artefacts

| File | SHA-256, line endings normalised to LF | Bytes |
|---|---|---|
| `supabase/migrations/20260921000001_p0_invitation_containment.sql` | `38e3142ef20602ef82fb9b2e365b932bf0e6481399f58e876a3a2634e0e1bd39` | 27,290 |
| `scripts/rollback-p0-invitation-containment.sql` | `23b84826d204acf187630bc2dfb5ca739e52e29e3f1181ced227d3d62b80a5a0` | 7,604 |

## The steps

**Close the current Supabase tab entirely.** It is in a desynchronised state and must not be used.

**Open a completely fresh browser tab** and sign in to the production project, then open the SQL
Editor and create a new query.

**Verify the migration hash yourself** before copying anything. In PowerShell:

```powershell
$p = 'C:\Users\tapiw\work\amari-reviewer-access\supabase\migrations\20260921000001_p0_invitation_containment.sql'
$b = [System.IO.File]::ReadAllBytes($p)
$lf = [System.Text.Encoding]::UTF8.GetString($b) -replace "`r`n", "`n"
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($lf)) | ForEach-Object { $_.ToString('x2') }) -join ''
$hash
$lf.Length
```

It must print `38e3142ef20602ef82fb9b2e365b932bf0e6481399f58e876a3a2634e0e1bd39` and `27290`. If
either differs, stop and say so. Do not run it.

**Capture the reissue list first.** Open `secure-output/pending-reissue-list.sql`, run it in the
editor, and save the result somewhere private. It must return exactly **nine** rows. This has to
happen before the migration, because afterwards those rows are expired and the query no longer
finds them. Do not paste this output into chat; it contains names and email addresses.

**Capture a fresh before state.** Run statement one of
`scripts/verify-production-reviewer-prerequisites.sql` and save the grid, immediately before the
migration and in the same session. Do not reuse the earlier baseline from 08:01, even though its
counts still match. A grid captured an hour earlier says nothing about the state at the moment of
the write, and the point of a before grid is to be paired with the after grid across the smallest
possible gap.

**Copy the migration file once** and paste it into the fresh editor. Do not type it, do not paste
in pieces.

**Check the paste visually.** The first non-comment line should be `begin;`. Scroll to the bottom:
the last line should be `commit;`. There should be exactly one of each. If anything else appears at
the top or bottom, clear the editor and paste again.

**Run it.**

**The Supabase warning will appear**, saying the query creates a table without row level security.
Choose **Run without RLS**. That means run the SQL as written rather than let Supabase add its own
statements. The migration enables and forces row level security on that table itself, and revokes
access from `public`, `anon` and `authenticated`, all before the single commit. Choosing the other
option would alter the hash-verified SQL.

**Expect these notices:**

```
NOTICE:  map_projects smoke test returned N rows
NOTICE:  map_states smoke test returned N rows
NOTICE:  map_countries smoke test returned N rows
NOTICE:  containment complete. 1216 legacy invitations expired, 9 secure replacements created,
         23 members and 4 administrators unchanged
```

If any assertion raises instead, nothing has committed and production is unchanged. Copy the error
and stop.

**Immediately run the post-deployment verification** from step 3 of
`docs/P0_CONTAINMENT_DEPLOY_RUNBOOK.md`, then statement one of the prerequisites script again as
the after grid.

**Paste back only the non-sensitive grids.** Counts, object names and grant booleans are fine. Do
not paste invitation codes, recipient names or email addresses.

## Required results

| Control | Required after |
|---|---|
| Valid unused invitations | 9, all `invite_source = 'reissue'` |
| Valid unused admin-capable | 0 |
| Valid unused bootstrap or predictable | 0 |
| Valid unused with a weak random component | 0 |
| Replacements failing their own requirements | 0 |
| Members | 23 |
| Administrator roles | 4, one owner and three admins |
| Redeemed invitations | 24 |
| Rows captured for rollback | 1,216 |
| `anon` execute on redemption, the map trio, and the rate limit pair | false |
| `anon` execute on `validate_invitation_code` | true, unchanged |

## Then stop

Do not distribute any replacement code until the device checks below pass.

## Device checks, iPhone, by hand

- Complete one ordinary onboarding using one of the nine replacements. It must succeed at the
  intended tier. This is the only real proof that the 48-character code format works on the shipped
  client, which imposes no length or pattern limit in source but has never been exercised with a
  code this long.
- Open the Aligned map as an existing gold or above member. It must load.
- Sign in as an administrator, confirm the admin panels load, and change a test member's tier.
- Confirm an ordinary member and a silver member cannot reach the Aligned map.

## If something breaks

Use the smallest rollback section that fixes it. Section 2 restores the grants and is almost always
the right one. **Do not run section 1**, which restores the old expiries and would make the 1,216
weak invitations valid again. **Do not run section 5**, which restores the vulnerable redemption
function. A legacy or 32-bit code no longer working is the intended effect, not a fault.

Report before running any rollback that would reopen the authorisation vulnerability.
