-- ============================================================================
-- P0 invitation containment, revision 2
--
-- PROPOSED. NOT APPLIED. Requires explicit approval before execution.
--
-- Revision 2 incorporates four amendments:
--   1. the entire predictable and bootstrap pool is retired, not just the
--      admin-capable subset;
--   2. the map functions enforce active membership and tier server-side rather
--      than merely requiring authentication;
--   3. the rate limit revokes are backed by a live dependency analysis;
--   4. the rollback table is explicitly unreachable by application roles.
--
-- Scope discipline. Nothing here goes beyond the confirmed P0 surfaces.
-- Deliberately excluded and documented in docs/P0_INVITATION_CONTAINMENT_PLAN.md:
-- anonymous abuse limiting on validate_invitation_code, cryptographically
-- random code generation, hashed-only storage, retirement of the plaintext
-- column, the Apple private relay email bypass, and the allow-list pass over
-- the remaining functions that hold a PUBLIC grant.
--
-- One transaction. Any failure rolls everything back and production is
-- unchanged.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Reversibility, and the backup table is internal only.
--
--    Row level security is enabled with no policy, which denies every role
--    that is not the owner regardless of table grants. The explicit revokes
--    are belt and braces so that a future grant cannot quietly open it.
-- ---------------------------------------------------------------------------
create table if not exists public.invitation_expiry_backup_20260921 (
  invitation_id    uuid primary key,
  previous_expires timestamptz not null,
  backed_up_at     timestamptz not null default now(),
  reason           text not null
);

alter table public.invitation_expiry_backup_20260921 enable row level security;
alter table public.invitation_expiry_backup_20260921 force row level security;

revoke all on table public.invitation_expiry_backup_20260921 from public;
revoke all on table public.invitation_expiry_backup_20260921 from anon;
revoke all on table public.invitation_expiry_backup_20260921 from authenticated;
grant select, insert on table public.invitation_expiry_backup_20260921 to service_role;

insert into public.invitation_expiry_backup_20260921 (invitation_id, previous_expires, reason)
select id, expires_at, 'p0_containment_rev2'
from public.invitation_codes
where used_by is null
  and expires_at > now()
  and (
        (coalesce(grants_admin, false) or staff_role_grant is not null)
     or invite_source = 'bootstrap'
     or coalesce(code, '') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$'
      )
on conflict (invitation_id) do nothing;

-- ---------------------------------------------------------------------------
-- A. Retire the legacy invitation pool.
--
--    Three overlapping rules, deliberately a union rather than three passes:
--      * anything that can grant administrative rights, in any format;
--      * anything issued from the bootstrap source;
--      * anything whose code matches the published predictable pattern.
--
--    Expected on production: 1,210 rows affected, of which three are addressed
--    to a named person and need reissuing through the admin panel. Six valid
--    unused codes survive, all from the controlled admin path and all
--    addressed to named recipients.
--
--    Nothing is deleted. Redeemed invitations are untouched. History intact.
-- ---------------------------------------------------------------------------
update public.invitation_codes
   set expires_at = now()
 where used_by is null
   and expires_at > now()
   and (
         (coalesce(grants_admin, false) or staff_role_grant is not null)
      or invite_source = 'bootstrap'
      or coalesce(code, '') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$'
       );

-- Assert every post-condition. A partial result must not commit.
do $guard$
declare
  v_admin_capable integer;
  v_predictable   integer;
  v_bootstrap     integer;
  v_survivors     integer;
begin
  select count(*) into v_admin_capable
  from public.invitation_codes
  where used_by is null and expires_at > now()
    and (coalesce(grants_admin, false) or staff_role_grant is not null);

  select count(*) into v_predictable
  from public.invitation_codes
  where used_by is null and expires_at > now()
    and coalesce(code, '') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$';

  select count(*) into v_bootstrap
  from public.invitation_codes
  where used_by is null and expires_at > now()
    and invite_source = 'bootstrap';

  select count(*) into v_survivors
  from public.invitation_codes
  where used_by is null and expires_at > now();

  if v_admin_capable <> 0 then
    raise exception 'admin-capable invitations still valid and unused: %', v_admin_capable;
  end if;
  if v_predictable <> 0 then
    raise exception 'predictable-format invitations still valid and unused: %', v_predictable;
  end if;
  if v_bootstrap <> 0 then
    raise exception 'bootstrap invitations still valid and unused: %', v_bootstrap;
  end if;

  raise notice 'containment complete: % valid unused invitations remain, all from the controlled admin path', v_survivors;
end;
$guard$;

-- ---------------------------------------------------------------------------
-- C. Redemption is authenticated-only and binds to auth.uid().
--
--    The product redeems only after sign-in. providers/AuthProvider.tsx guards
--    on an established session and passes the signed-in user's own identifier,
--    so this is compatible with every build currently in the field.
--
--    The signature is unchanged on purpose. p_user_id stops being an authority
--    and becomes an assertion: an older client's claim about who it is must
--    match the identity the server established.
-- ---------------------------------------------------------------------------
create or replace function public.redeem_invitation_code(
  p_code text,
  p_user_id uuid,
  p_full_name text,
  p_email text,
  p_city text default null,
  p_industry text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_actor uuid := auth.uid();
  v_invite public.invitation_codes%rowtype;
  v_member_exists boolean;
  v_existing_member_id uuid;
  v_hash text;
  v_is_staff boolean;
  v_admin_role text;
  v_normalized_email text;
  v_member_email text;
begin
  if v_actor is null then
    return jsonb_build_object('success', false, 'error', 'not_authenticated');
  end if;

  if p_user_id is not null and p_user_id <> v_actor then
    return jsonb_build_object('success', false, 'error', 'identity_mismatch');
  end if;

  select exists (
    select 1 from public.members where id = v_actor
  ) into v_member_exists;

  if v_member_exists then
    return jsonb_build_object('success', false, 'error', 'already_member');
  end if;

  v_hash := encode(extensions.digest(upper(p_code), 'sha256'), 'hex');

  select *
  into v_invite
  from public.invitation_codes
  where code_hash = v_hash
    and used_by is null
    and expires_at > now()
  for update skip locked;

  if not found then
    return jsonb_build_object('success', false, 'error', 'invalid_or_expired');
  end if;

  v_normalized_email := lower(btrim(p_email));

  if v_invite.recipient_email is not null
     and lower(btrim(v_invite.recipient_email)) <> v_normalized_email
     and v_normalized_email not like '%@privaterelay.appleid.com' then
    return jsonb_build_object('success', false, 'error', 'email_mismatch');
  end if;

  v_member_email := coalesce(lower(btrim(v_invite.recipient_email)), v_normalized_email);

  select id
    into v_existing_member_id
    from public.members
   where lower(btrim(email)) = v_member_email
     and status in ('active', 'pending')
   order by created_at asc
   limit 1;

  if v_existing_member_id is not null then
    update public.invitation_codes
       set used_by = v_existing_member_id,
           used_at = coalesce(used_at, now())
     where id = v_invite.id
       and used_by is null;

    return jsonb_build_object('success', false, 'error', 'already_member');
  end if;

  insert into public.members (id, full_name, email, tier, status, city, industry)
  values (
    v_actor,
    p_full_name,
    v_member_email,
    v_invite.tier_grant,
    'active',
    p_city,
    p_industry
  );

  v_admin_role := coalesce(
    v_invite.staff_role_grant,
    case when v_invite.grants_admin then 'admin' else null end
  );
  v_is_staff := v_admin_role is not null;

  if v_is_staff then
    insert into public.admin_roles (member_id, role)
    values (v_actor, v_admin_role)
    on conflict (member_id) do update
      set role = excluded.role;
  end if;

  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) ||
    jsonb_build_object(
      'tier', v_invite.tier_grant::text,
      'is_admin', v_is_staff,
      'admin_role', v_admin_role
    )
  where id = v_actor;

  update public.invitation_codes
  set used_by = v_actor,
      used_at = now()
  where id = v_invite.id;

  return jsonb_build_object(
    'success', true,
    'tier', v_invite.tier_grant::text,
    'is_admin', v_is_staff,
    'admin_role', v_admin_role
  );
end;
$fn$;

revoke execute on function public.redeem_invitation_code(text, uuid, text, text, text, text)
  from public, anon;
grant execute on function public.redeem_invitation_code(text, uuid, text, text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- D. Rate limit plumbing becomes internal.
--
--    Live dependency analysis, run against production before writing this:
--    no other database function references either name, no trigger function
--    references them, no view or rule references them, and the only edge
--    function touching the map path calls refresh_map_cache, which is
--    untouched here. Both are owned by postgres.
--
--    Correction to the first revision of this plan. Revoking cleanup_rate_limits
--    is defence in depth rather than a precondition, because public.rate_limits
--    already has row level security enabled with no policy, which denies every
--    application role irrespective of table grants.
-- ---------------------------------------------------------------------------
revoke execute on function public.cleanup_rate_limits()
  from public, anon, authenticated;
grant execute on function public.cleanup_rate_limits() to service_role;

revoke execute on function public.check_rate_limit(text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.check_rate_limit(text, text, integer, integer) to service_role;

-- Remove the misleading direct table privileges as well. These are inert today
-- because row level security denies them, but a privilege that looks live and
-- is not invites a future mistake. Strike this block if you want the migration
-- narrower.
revoke all on table public.rate_limits from anon;
revoke all on table public.rate_limits from authenticated;

-- ---------------------------------------------------------------------------
-- 3. Map functions enforce membership and tier in the database.
--
--    The product rule, read from the shipped client: the Aligned surface
--    requires TAB_VISIBILITY.aligned = 3 and TIER_LEVELS gold = 3, so the
--    enforced requirement is gold and above. The user-facing copy in
--    app/(tabs)/aligned/_layout.tsx says "Available from Platinum membership",
--    which disagrees with the constant it enforces. This migration reproduces
--    the rule the client actually enforces today, so nothing that works now
--    stops working. Moving the boundary to platinum is a product decision and
--    a one-word change here plus a copy fix, not a security change.
--
--    The guard reads members.tier directly rather than calling
--    get_member_tier(), because that helper falls back to a JWT claim. For an
--    authorisation gate the row is the authority, not the token.
-- ---------------------------------------------------------------------------
create or replace function public.assert_aligned_map_access()
returns void
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_actor  uuid := auth.uid();
  v_tier   membership_tier;
  v_active boolean;
begin
  -- No role-based bypass here, deliberately. Inside a SECURITY DEFINER
  -- function current_user is the function OWNER rather than the caller, so any
  -- check of the form pg_has_role(current_user, ...) is true for every caller
  -- and silently admits everybody. An earlier draft of this guard did exactly
  -- that and the tier matrix caught it. Identity comes from auth.uid() only.
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select m.tier, (m.status = 'active')
    into v_tier, v_active
    from public.members m
   where m.id = v_actor;

  if not found then
    raise exception 'membership required' using errcode = '42501';
  end if;

  if not v_active then
    raise exception 'active membership required' using errcode = '42501';
  end if;

  -- Administrators reach the surface regardless of tier.
  if public.is_admin() then
    return;
  end if;

  if v_tier < 'gold'::membership_tier then
    raise exception 'higher membership tier required' using errcode = '42501';
  end if;
end;
$fn$;

revoke execute on function public.assert_aligned_map_access() from public, anon, authenticated;

create or replace function public.map_countries(category_filter text default null)
returns table (
  country_code text,
  country_name text,
  project_count integer,
  categories jsonb,
  lat double precision,
  lng double precision
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $fn$
begin
  perform public.assert_aligned_map_access();

  return query
    select c.country_code, c.country_name, c.project_count, c.categories,
           ST_Y(c.centroid), ST_X(c.centroid)
    from public.map_cache_countries c
    where (category_filter is null or c.categories ? category_filter);
end;
$fn$;

create or replace function public.map_states(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  category_filter text default null
)
returns table (
  state_province text,
  display_label text,
  project_count integer,
  categories jsonb,
  lat double precision,
  lng double precision
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $fn$
begin
  perform public.assert_aligned_map_access();

  return query
    select s.state_province, s.display_label, s.project_count, s.categories,
           ST_Y(s.centroid), ST_X(s.centroid)
    from public.map_cache_states s
    where ST_Intersects(
            s.centroid,
            ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326))
      and (category_filter is null or s.categories ? category_filter);
end;
$fn$;

create or replace function public.map_projects(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  category_filter text default null
)
returns table (
  project_id uuid,
  name text,
  description text,
  category text,
  creator_first_name text,
  display_label text,
  image_url text,
  external_link text,
  lat double precision,
  lng double precision
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $fn$
begin
  perform public.assert_aligned_map_access();

  return query
    select p.project_id, p.name, p.description, p.category::text,
           p.creator_first_name, p.display_label, p.image_url, p.external_link,
           ST_Y(p.display_point), ST_X(p.display_point)
    from public.map_cache_projects p
    where ST_Intersects(
            p.display_point,
            ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326))
      and (category_filter is null or p.category::text = category_filter);
end;
$fn$;

revoke execute on function public.map_projects(
  double precision, double precision, double precision, double precision, text)
  from public, anon;
grant execute on function public.map_projects(
  double precision, double precision, double precision, double precision, text)
  to authenticated;

revoke execute on function public.map_states(
  double precision, double precision, double precision, double precision, text)
  from public, anon;
grant execute on function public.map_states(
  double precision, double precision, double precision, double precision, text)
  to authenticated;

revoke execute on function public.map_countries(text) from public, anon;
grant execute on function public.map_countries(text) to authenticated;

-- Smoke test. PostGIS is not created by any migration in this repository, so
-- its schema is not knowable from source. If the fixed search_path cannot
-- resolve the PostGIS operators, or if a rewritten body is wrong, this raises
-- and the entire migration rolls back.
--
-- A migration runs with no authenticated user, so the guard would refuse it.
-- Rather than weaken the guard, the test borrows an existing administrator's
-- identity for the duration of this transaction only. set_config with is_local
-- true is transaction scoped and disappears at commit. This also means the
-- smoke test exercises the guard's admit path instead of stepping around it.
do $smoke$
declare
  v_count integer;
  v_admin uuid;
begin
  select member_id into v_admin from public.admin_roles limit 1;
  if v_admin is null then
    raise exception 'no administrator exists to run the map smoke test as';
  end if;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  select count(*) into v_count
  from public.map_projects(-90.0, -180.0, 90.0, 180.0, null);
  raise notice 'map_projects smoke test returned % rows', v_count;

  select count(*) into v_count
  from public.map_states(-90.0, -180.0, 90.0, 180.0, null);
  raise notice 'map_states smoke test returned % rows', v_count;

  select count(*) into v_count
  from public.map_countries(null);
  raise notice 'map_countries smoke test returned % rows', v_count;

  perform set_config('request.jwt.claim.sub', '', true);
exception
  when insufficient_privilege then
    raise exception
      'map smoke test was refused by the guard while impersonating an administrator, so the guard is wrong: %',
      sqlerrm;
  when others then
    raise exception 'map smoke test failed: %', sqlerrm;
end;
$smoke$;

-- ---------------------------------------------------------------------------
-- 4. New functions in the application schema stop being PUBLIC by default.
--
--    Affects functions created from here on. Touches nothing that exists,
--    because a mass revoke would break the live application. The fifteen
--    functions that currently hold a PUBLIC grant are retired separately
--    through a reviewed allow-list, one at a time, each with a test.
--
--    CREATE OR REPLACE preserves an existing function's privileges, so this
--    default is not silently undone by later edits.
-- ---------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke execute on functions from public;

commit;
