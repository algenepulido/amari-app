-- Schema signature. Metadata and types only. Read only.
-- Run identically against production and against the disposable fixture, then
-- diff the two outputs mechanically.
select 'col' as kind,
       c.table_name || '.' || c.column_name as object,
       c.data_type || ' / ' || c.udt_name || ' / nullable=' || c.is_nullable as signature
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name in ('invitation_codes', 'admin_roles', 'members', 'rate_limits')
  and c.column_name in (
    'id','expires_at','used_by','used_at','grants_admin','staff_role_grant',
    'invite_source','code','code_hash','code_prefix','recipient_name','recipient_email',
    'tier_grant','issued_at','issued_by','member_id','role','tier','status',
    'full_name','email','city','industry','key','endpoint','created_at'
  )

union all

select 'fn',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       'returns ' || pg_get_function_result(p.oid)
         || ' / secdef=' || p.prosecdef::text
         || ' / lang=' || l.lanname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname = 'public'
  and p.proname in (
    'redeem_invitation_code','validate_invitation_code','check_rate_limit',
    'cleanup_rate_limits','map_projects','map_states','map_countries',
    'is_admin','is_active_member','get_member_tier','generate_share_invite_code',
    'assert_aligned_map_access'
  )

union all

select 'enum',
       t.typname,
       string_agg(e.enumlabel, ',' order by e.enumsortorder)
from pg_type t
join pg_enum e on e.enumtypid = t.oid
join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'public' and t.typname in ('membership_tier', 'member_status')
group by t.typname

order by 1, 2, 3;
