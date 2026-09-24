-- ============================================================================
-- Production reviewer prerequisite verification, READ ONLY
--
-- Prepared 21 September 2026 for the external reviewer programme.
-- Target: the production Supabase project used by the AMARI iOS application.
--
-- This file contains no INSERT, UPDATE, DELETE, ALTER, DROP, CREATE, GRANT,
-- REVOKE, TRUNCATE or COMMENT statement, and calls no function that changes
-- state. Everything here is a SELECT over catalogue metadata and counts.
--
-- It returns no invitation code, no code hash, no email address, no member
-- personal information, no token and no secret. The plaintext invitation code
-- column is read inside a pattern predicate only, so that predictable code
-- formats can be counted. Its value never reaches the output.
--
-- HOW TO RUN
-- There are two statements, separated below. The Supabase SQL Editor shows the
-- result of the last statement only, so run them one at a time: highlight a
-- statement and press run, copy the whole grid, then do the same for the other.
-- Statement two is separated because it reads the Supabase migration ledger,
-- which is not present in every project. If statement two errors, that error is
-- itself a finding and statement one is unaffected.
-- ============================================================================


-- ===========================================================================
-- STATEMENT ONE. Sections 0 to 4.
-- Context, invitation state, security definer inventory and live grants,
-- named high risk functions, and row level security.
-- ===========================================================================

with role_present as (
  select
    exists (select 1 from pg_roles where rolname = 'anon')          as has_anon,
    exists (select 1 from pg_roles where rolname = 'authenticated') as has_authenticated,
    exists (select 1 from pg_roles where rolname = 'service_role')  as has_service_role
),

fn as (
  select
    p.oid,
    n.nspname::text                                 as schema_name,
    p.proname::text                                 as fn_name,
    pg_get_function_identity_arguments(p.oid)       as args,
    pg_get_userbyid(p.proowner)::text               as owner,
    p.prosecdef                                     as security_definer,
    coalesce(array_to_string(p.proconfig, ' '), '') as fn_config,
    p.proacl,
    p.prorettype::regtype::text                     as return_type,
    p.prosrc                                        as body
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'
),

fn_priv as (
  select
    f.*,
    (f.proacl is null) as acl_is_default,
    case
      when f.proacl is null then true
      else exists (
        select 1 from aclexplode(f.proacl) a
        where a.grantee = 0 and a.privilege_type = 'EXECUTE'
      )
    end as public_execute,
    case when (select has_anon from role_present)
         then has_function_privilege('anon', f.oid, 'EXECUTE') end          as anon_execute,
    case when (select has_authenticated from role_present)
         then has_function_privilege('authenticated', f.oid, 'EXECUTE') end as authenticated_execute,
    case when (select has_service_role from role_present)
         then has_function_privilege('service_role', f.oid, 'EXECUTE') end  as service_role_execute,
    (f.fn_config ilike '%search_path%')     as sets_search_path,
    (position('auth.uid()' in f.body) > 0)  as references_auth_uid,
    (position('is_admin' in f.body) > 0)    as references_is_admin,
    (position('admin_roles' in f.body) > 0) as touches_admin_roles
  from fn f
),

inv as (
  select
    count(*)                                                        as total_rows,
    count(*) filter (where used_by is null and expires_at > now())  as valid_unused,
    count(*) filter (where used_by is not null)                     as redeemed,
    count(*) filter (where used_by is null and expires_at <= now()) as unused_expired,
    count(*) filter (where code is not null)                        as plaintext_code_still_stored,
    count(*) filter (
      where used_by is null and expires_at > now()
        and (coalesce(grants_admin, false) or staff_role_grant is not null)
    ) as valid_unused_admin_capable,
    count(*) filter (
      where used_by is null and expires_at <= now()
        and (coalesce(grants_admin, false) or staff_role_grant is not null)
    ) as expired_unused_admin_capable,
    count(*) filter (
      where used_by is not null
        and (coalesce(grants_admin, false) or staff_role_grant is not null)
    ) as redeemed_admin_capable,
    count(*) filter (
      where used_by is null and expires_at > now()
        and coalesce(code, '') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$'
    ) as valid_unused_predictable_format,
    count(*) filter (
      where used_by is null and expires_at > now()
        and coalesce(code, '') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$'
        and (coalesce(grants_admin, false) or staff_role_grant is not null)
    ) as valid_unused_predictable_admin,
    count(*) filter (
      where used_by is null and expires_at > now() and invite_source = 'bootstrap'
    ) as valid_unused_bootstrap
  from public.invitation_codes
),

inv_by_tier as (
  select
    coalesce(tier_grant::text, 'null')                             as tier,
    count(*) filter (where used_by is null and expires_at > now()) as valid_unused
  from public.invitation_codes
  group by 1
),

tbl as (
  select
    c.relname::text       as table_name,
    c.relrowsecurity      as rls_enabled,
    c.relforcerowsecurity as rls_forced,
    (select count(*) from pg_policies p
      where p.schemaname = 'public' and p.tablename = c.relname) as policy_count,
    (select coalesce(string_agg(distinct r::text, ','), 'none')
       from pg_policies p, unnest(p.roles) as r
      where p.schemaname = 'public' and p.tablename = c.relname) as policy_roles
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
),

out as (

  -- 0. run context
  select '0.0' as sort_key, '0 context' as section, 'database' as subject,
         'current_database' as metric, current_database()::text as value
  union all select '0.1', '0 context', 'database', 'server_version', version()
  union all select '0.2', '0 context', 'database', 'run_at_utc', (now() at time zone 'utc')::text
  union all select '0.3', '0 context', 'roles', 'anon_role_exists',
                   (select has_anon::text from role_present)
  union all select '0.4', '0 context', 'roles', 'authenticated_role_exists',
                   (select has_authenticated::text from role_present)
  union all select '0.5', '0 context', 'roles', 'service_role_exists',
                   (select has_service_role::text from role_present)

  -- 1. invitation and admin bootstrap state, counts only
  union all select '1.01', '1 invitations', 'all codes', 'total_rows', total_rows::text from inv
  union all select '1.02', '1 invitations', 'all codes', 'valid_unused', valid_unused::text from inv
  union all select '1.03', '1 invitations', 'all codes', 'redeemed', redeemed::text from inv
  union all select '1.04', '1 invitations', 'all codes', 'unused_but_expired',
                   unused_expired::text from inv
  union all select '1.05', '1 invitations', 'all codes',
                   'rows_where_plaintext_code_column_not_null',
                   plaintext_code_still_stored::text from inv
  union all select '1.06', '1 invitations', 'ADMIN CAPABLE', 'valid_unused_admin_capable',
                   valid_unused_admin_capable::text from inv
  union all select '1.07', '1 invitations', 'ADMIN CAPABLE', 'expired_unused_admin_capable',
                   expired_unused_admin_capable::text from inv
  union all select '1.08', '1 invitations', 'ADMIN CAPABLE', 'redeemed_admin_capable',
                   redeemed_admin_capable::text from inv
  union all select '1.09', '1 invitations', 'predictable format',
                   'valid_unused_predictable_format',
                   valid_unused_predictable_format::text from inv
  union all select '1.10', '1 invitations', 'predictable format',
                   'VALID_UNUSED_PREDICTABLE_AND_ADMIN_CAPABLE',
                   valid_unused_predictable_admin::text from inv
  union all select '1.11', '1 invitations', 'bootstrap source', 'valid_unused_bootstrap',
                   valid_unused_bootstrap::text from inv
  union all select '1.20', '1 invitations', 'by tier: ' || tier, 'valid_unused',
                   valid_unused::text from inv_by_tier

  -- 2. security definer inventory with live grants
  union all select '2.00', '2 secdef summary', 'public schema', 'functions_total',
                   count(*)::text from fn_priv
  union all select '2.01', '2 secdef summary', 'public schema', 'security_definer_total',
                   count(*) filter (where security_definer)::text from fn_priv
  union all select '2.02', '2 secdef summary', 'public schema', 'secdef_executable_by_public',
                   count(*) filter (where security_definer and public_execute)::text from fn_priv
  union all select '2.03', '2 secdef summary', 'public schema', 'secdef_executable_by_anon',
                   count(*) filter (where security_definer and anon_execute)::text from fn_priv
  union all select '2.04', '2 secdef summary', 'public schema',
                   'secdef_executable_by_authenticated',
                   count(*) filter (where security_definer and authenticated_execute)::text
                   from fn_priv
  union all select '2.05', '2 secdef summary', 'public schema', 'secdef_without_search_path',
                   count(*) filter (where security_definer and not sets_search_path)::text
                   from fn_priv
  union all select '2.06', '2 secdef summary', 'public schema',
                   'secdef_anon_callable_without_auth_uid',
                   count(*) filter (
                     where security_definer and anon_execute and not references_auth_uid
                   )::text from fn_priv
  union all select
    '2.10', '2 secdef inventory',
    fn_name || '(' || args || ')',
    'owner=' || owner
      || ' search_path=' || sets_search_path::text
      || ' acl_default=' || acl_is_default::text,
    'public=' || public_execute::text
      || ' anon=' || coalesce(anon_execute::text, 'n/a')
      || ' authenticated=' || coalesce(authenticated_execute::text, 'n/a')
      || ' service_role=' || coalesce(service_role_execute::text, 'n/a')
      || ' auth_uid=' || references_auth_uid::text
      || ' admin_roles=' || touches_admin_roles::text
    from fn_priv where security_definer

  -- 3. named high risk functions, and anything that can write tier or admin state
  union all select
    '3.10', '3 high risk named',
    fn_name || '(' || args || ')',
    'returns=' || return_type
      || ' secdef=' || security_definer::text
      || ' search_path=' || sets_search_path::text
      || ' auth_uid=' || references_auth_uid::text
      || ' admin_roles=' || touches_admin_roles::text,
    'public=' || public_execute::text
      || ' anon=' || coalesce(anon_execute::text, 'n/a')
      || ' authenticated=' || coalesce(authenticated_execute::text, 'n/a')
      || ' body_md5=' || md5(body)
    from fn_priv
    where fn_name in (
      'validate_invitation_code', 'redeem_invitation_code',
      'check_rate_limit', 'cleanup_rate_limits',
      'map_projects', 'map_states', 'map_countries',
      'change_member_tier', 'admin_create_invitation_code', 'create_monthly_invite',
      'admin_set_member_status', 'is_admin', 'is_active_member', 'get_member_tier',
      'custom_access_token_hook'
    )
  union all select
    '3.20', '3 tier or admin writers',
    fn_name || '(' || args || ')',
    'secdef=' || security_definer::text || ' auth_uid=' || references_auth_uid::text
      || ' is_admin_check=' || references_is_admin::text,
    'anon=' || coalesce(anon_execute::text, 'n/a')
      || ' authenticated=' || coalesce(authenticated_execute::text, 'n/a')
      || ' public=' || public_execute::text
    from fn_priv
    where touches_admin_roles
       or body ~* 'raw_app_meta_data'
       or body ~* 'public\.members[[:space:]]+set[[:space:]]+tier'
  union all select
    '3.30', '3 rate limiting present',
    fn_name || '(' || args || ')',
    'name matches rate limit',
    'anon=' || coalesce(anon_execute::text, 'n/a')
      || ' authenticated=' || coalesce(authenticated_execute::text, 'n/a')
    from fn_priv
    where fn_name ~* 'rate.?limit|throttle'

  -- 4. row level security
  union all select '4.00', '4 rls summary', 'public schema', 'tables_total',
                   count(*)::text from tbl
  union all select '4.01', '4 rls summary', 'public schema', 'tables_without_rls',
                   count(*) filter (where not rls_enabled)::text from tbl
  union all select '4.02', '4 rls summary', 'public schema', 'tables_with_rls_but_no_policy',
                   count(*) filter (where rls_enabled and policy_count = 0)::text from tbl
  union all select
    '4.10', '4 rls detail', table_name,
    'rls=' || rls_enabled::text || ' forced=' || rls_forced::text
      || ' policies=' || policy_count::text,
    'roles=' || policy_roles
    from tbl
)

select section, subject, metric, value
from out
order by sort_key, subject, metric;


-- ===========================================================================
-- STATEMENT TWO. Section 6. Applied migration ledger, for repository drift.
-- Run this separately. If it errors because the schema is absent, report the
-- error text rather than the rows, because the absence is itself the finding.
-- ===========================================================================

select
  '6 migrations'      as section,
  'applied_version'   as subject,
  version::text       as metric,
  ''                  as value
from supabase_migrations.schema_migrations
order by version;
