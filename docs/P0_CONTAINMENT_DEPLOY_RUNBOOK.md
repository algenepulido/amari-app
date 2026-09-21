# P0 containment deployment runbook, revision 3

Prepared 21 September 2026. Not executed. Requires an explicit go.

Migration: `supabase/migrations/20260921000001_p0_invitation_containment.sql`
SHA-256, line endings normalised to LF: `38e3142ef20602ef82fb9b2e365b932bf0e6481399f58e876a3a2634e0e1bd39`
Size: 27,290 bytes. One transaction. No `drop table`, no `delete`, no `truncate`.

## What changed in revision 3

The expiry of the weak invitations and the creation of their secure replacements now happen inside
the same transaction. There is no interval in which both are valid, and no interval after
containment in which a 32-bit code survives. The new secrets are generated inside that transaction
rather than prepared beforehand.

## Step 0, capture the reissue targets

Run `secure-output/pending-reissue-list.sql` and save its output somewhere private. It lists the
nine people holding a pending invitation that this transaction expires, with the intended tier for
each, and marks which of them held a weak 32-bit code.

It is gitignored because the output contains names and email addresses. It must be run first: the
transaction expires those rows, after which the predicate no longer matches them and the only trace
is the backup table keyed by identifier.

You do not feed this list back into anything. The transaction derives the replacements from the
rows themselves. The list is for your records and for knowing whom to contact afterwards.

**Confirm the row count is nine before proceeding.** If it is not nine, stop and say so, because
the live state has moved since the 21 September baseline.

## Step 1, capture the before state

Run and save each grid, named `docs/evidence/before-<timestamp>-*.csv`:

- `scripts/verify-production-reviewer-prerequisites.sql`, statement one
- `scripts/verify-admin-role-reconciliation.sql`

## Step 2, apply the migration

Paste the whole file and run it once. Expect:

```
NOTICE:  map_projects smoke test returned N rows
NOTICE:  map_states smoke test returned N rows
NOTICE:  map_countries smoke test returned N rows
NOTICE:  containment complete. 1216 legacy invitations expired, 9 secure replacements created,
         23 members and 4 administrators unchanged
```

If any assertion raises, nothing commits and production is unchanged. That is a safe outcome. Read
the message and stop.

## Step 3, immediate read-only verification

```sql
select 'valid_unused_total' as control, count(*)::text as value
from public.invitation_codes where used_by is null and expires_at > now()
union all select 'valid_unused_admin_capable', count(*)::text
from public.invitation_codes where used_by is null and expires_at > now()
  and (coalesce(grants_admin,false) or staff_role_grant is not null)
union all select 'valid_unused_bootstrap', count(*)::text
from public.invitation_codes where used_by is null and expires_at > now()
  and invite_source = 'bootstrap'
union all select 'valid_unused_predictable_legacy', count(*)::text
from public.invitation_codes where used_by is null and expires_at > now()
  and coalesce(code,'') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$'
union all select 'valid_unused_weak_suffix', count(*)::text
from public.invitation_codes where used_by is null and expires_at > now()
  and code is not null and length(code) - length(code_prefix) - 1 < 40
union all select 'valid_unused_replacements', count(*)::text
from public.invitation_codes where used_by is null and expires_at > now()
  and invite_source = 'reissue'
union all select 'replacements_failing_requirements', count(*)::text
from public.invitation_codes where invite_source = 'reissue'
  and (recipient_email is null or coalesce(grants_admin,false) is true
       or staff_role_grant is not null or used_by is not null
       or expires_at <= now() or length(code) - length(code_prefix) - 1 <> 48)
union all select 'members', count(*)::text from public.members
union all select 'admin_roles', count(*)::text from public.admin_roles
union all select 'invitations_redeemed', count(*)::text
from public.invitation_codes where used_by is not null
union all select 'backup_rows_for_rollback', count(*)::text
from public.invitation_expiry_backup_20260921;
```

Then re-run `scripts/verify-production-reviewer-prerequisites.sql` statement one in full and save it
as the after-state grid, beside the before-state grid.

## Step 4, the grant surface after

```sql
select p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated,
       exists (select 1 from aclexplode(p.proacl) a
               where a.grantee = 0 and a.privilege_type = 'EXECUTE') as public_execute
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('redeem_invitation_code','validate_invitation_code','check_rate_limit',
                    'cleanup_rate_limits','map_projects','map_states','map_countries',
                    'generate_share_invite_code')
order by 1;
```

Required: `anon` and `public_execute` false for everything except `validate_invitation_code`, which
keeps `anon` true because onboarding needs it before sign-in.

## Step 5, live product checks on a device

- Complete one ordinary onboarding using one of the nine replacements. Expect success at the
  intended tier. This is also the proof that the longer code format works on the shipped client.
- Open the Aligned map as an existing gold or above member. Expect it to load.
- Open an administrator account, confirm the panels load and a tier change on a test member works.
- From any REST client holding only the public anon key, call `rpc/redeem_invitation_code` and
  `rpc/map_projects` and expect a permission error rather than a result.

## Step 6, success criteria

| Control | Before | Required after |
|---|---|---|
| Valid unused admin-capable | 9 | 0 |
| Valid unused predictable or bootstrap | 1,209 | 0 |
| Valid unused with a weak random component | 1,216 | 0 |
| Valid unused replacements, 192-bit | 0 | 9 |
| All valid unused | 1,216 | 9 |
| Replacements failing their own requirements | — | 0 |
| Anonymous invitation redemption | allowed | denied |
| Anonymous map access | allowed | denied |
| Gold, platinum, laureate map access | not enforced | allowed |
| Member and silver map access | allowed | denied |
| Suspended member map access | allowed | denied |
| Members | 23 | 23 |
| Administrator roles | 4, one owner and three admins | 4, unchanged |
| Redeemed invitations | 24 | 24 |
| Rows captured for rollback | 0 | 1,216 |

## Step 7, distribute

Only after the after-state is clean, send each of the nine their replacement code. Retrieve the
values privately with a query restricted to `invite_source = 'reissue'`; do not print them into a
shared log.

## Rollback

`scripts/rollback-p0-invitation-containment.sql`, five sections, run only what is needed.

Trigger rollback if an existing member cannot sign in, valid onboarding fails for any reason other
than an expired invitation, a gold-or-above member cannot load the map, an administrator loses panel
access, any of the member, administrator or redeemed counts moves, or an edge function or scheduled
job starts failing on permissions.

A legacy or 32-bit code ceasing to work is the intended effect and is not a rollback trigger.

**Rollback implications for the nine replacements.** They are new rows, so rollback does not remove
them and should not. Restoring the old expiries with section 1 would make the old weak invitations
valid again alongside the new ones, which is the state we deliberately avoided. So: if rollback is
needed for a reason unrelated to invitations, run only sections 2 to 4 and leave section 1 alone. If
the replacements themselves must be withdrawn, expire them by `invite_source = 'reissue'` rather
than restoring the weak ones.

## Phase 2, recorded and not blocking this deployment

- Invitation codes should be stored hashed only; the plaintext column still holds every value.
- `validate_invitation_code` needs abuse and rate-limit protection with a trustworthy caller key.
- Enumeration responses should be minimised further.
- Legacy plaintext invitation history should be retired or nulled once the replacement path is
  proven.
- The remaining functions holding a PUBLIC grant need an allow-list pass, one at a time, each with a
  test.
