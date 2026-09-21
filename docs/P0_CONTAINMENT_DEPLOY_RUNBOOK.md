# P0 containment deployment runbook

Prepared 21 September 2026. Not executed. Requires an explicit go.

Migration: `supabase/migrations/20260921000001_p0_invitation_containment.sql`
SHA-256, line endings normalised to LF: `0f0198e8b6201d4b4229bdd53961b26ed15354c49f5573cdc9e88c02f4e0c76f`

## Step 0, before anything else

Run `secure-output/pending-reissue-list.sql` and save its output somewhere private. It names the
people holding a legacy invitation that this migration expires. It is gitignored because its output
contains names and email addresses, and it **must** be run first, because afterwards those rows are
expired and the predicate no longer matches them. There is no way to recover the list later except
from the backup table by identifier.

## Step 1, capture the before state

Run, in the SQL editor, and save each grid:

- `scripts/verify-production-reviewer-prerequisites.sql`, statement one.
- `scripts/verify-admin-role-reconciliation.sql`.

Save them as `docs/evidence/before-<timestamp>-*.csv` alongside the existing 21 September grids.

## Step 2, apply the migration

One transaction. Paste the whole file and run it once. Expect these notices:

```
NOTICE:  containment complete: 6 valid unused invitations remain, all from the controlled admin path
NOTICE:  map_projects smoke test returned N rows
NOTICE:  map_states smoke test returned N rows
NOTICE:  map_countries smoke test returned N rows
```

If any assertion raises, nothing commits and production is unchanged. That is a safe outcome, not
an incident. Read the message and stop.

## Step 3, immediate read-only verification

```sql
-- the four containment objectives
select 'admin_capable_valid_unused' as control, count(*)::text as value
from public.invitation_codes where used_by is null and expires_at > now()
  and (coalesce(grants_admin,false) or staff_role_grant is not null)
union all
select 'predictable_valid_unused', count(*)::text
from public.invitation_codes where used_by is null and expires_at > now()
  and coalesce(code,'') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$'
union all
select 'bootstrap_valid_unused', count(*)::text
from public.invitation_codes where used_by is null and expires_at > now()
  and invite_source = 'bootstrap'
union all
select 'all_valid_unused', count(*)::text
from public.invitation_codes where used_by is null and expires_at > now()
union all
select 'members', count(*)::text from public.members
union all
select 'admin_roles', count(*)::text from public.admin_roles
union all
select 'invitations_redeemed', count(*)::text from public.invitation_codes where used_by is not null
union all
select 'backup_rows_for_rollback', count(*)::text
from public.invitation_expiry_backup_20260921;
```

Then re-run `scripts/verify-production-reviewer-prerequisites.sql` statement one in full and save it
as the after-state grid, next to the before-state grid.

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
                    'cleanup_rate_limits','map_projects','map_states','map_countries')
order by 1;
```

Required: `anon` and `public_execute` false for everything except `validate_invitation_code`, which
keeps `anon` true because onboarding needs it before sign-in.

## Step 5, live product checks on a device

- Complete one ordinary onboarding end to end using one of the six surviving invitations, or a
  freshly issued one. Expect success at the invitation's tier.
- Open the Aligned map as an existing gold or above member. Expect the map to load.
- Open an administrator account and confirm the admin panels still load, and that a tier change on a
  test member still works.
- Confirm an anonymous caller is refused. From any REST client with only the public anon key, call
  `rpc/redeem_invitation_code` and `rpc/map_projects` and expect HTTP 404 or a permission error
  rather than a result.

## Step 6, success criteria

| Control | Before | Required after |
|---|---|---|
| Valid unused admin-capable invitations | 9 | 0 |
| Valid unused predictable or bootstrap invitations | 1,209 | 0 |
| All valid unused invitations | 1,216 | 6 |
| Anonymous invitation redemption | allowed | denied |
| Anonymous map access | allowed | denied |
| Gold, platinum, laureate map access | not enforced | allowed |
| Member and silver map access | allowed | denied |
| Suspended member map access | allowed | denied |
| Members | 23 | 23 |
| Administrator roles | 4, being one owner and three admins | 4, unchanged |
| Redeemed invitations | 24 | 24 |
| Rows captured for rollback | 0 | 1,210 |

## Step 7, reissue

Issue replacements to the people on the step 0 list through Admin then Codes. Note the entropy
caveat below before deciding whether to reissue through the existing generator or to wait for a
stronger one.

## Rollback

`scripts/rollback-p0-invitation-containment.sql`, five sections, run only what is needed.

Trigger rollback if any of the following is observed after deployment:

- an existing member cannot sign in, or an existing session breaks;
- onboarding with a valid invitation fails for a reason other than the invitation being expired;
- a gold or above member cannot load the Aligned map;
- an administrator loses access to an admin panel;
- the member count, administrator count or redeemed invitation count changes;
- any edge function or scheduled job begins failing on a permission error.

Section 2, the grants, is the one that matters if a client breaks. Section 1 restores the exact
prior expiries from the backup table. Section 5 restores the previous vulnerable function body and
should not be run unless the hardened one is proven to break something that cannot be fixed forward.

Do not trigger rollback merely because a legacy predictable code stopped working. That is the
intended effect.
