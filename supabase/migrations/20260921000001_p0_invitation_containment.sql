-- ============================================================================
-- P0 invitation containment, revision 3
--
-- PROPOSED. NOT APPLIED. Requires explicit approval before execution.
--
-- Revision 3 makes the whole sequence atomic. The weak invitations are expired
-- and their secure replacements are created inside one transaction, so there is
-- no interval in which both are valid, and no interval after containment in
-- which a 32-bit code survives.
--
-- Order inside the transaction:
--   A  back up the exact rows that will be invalidated
--   B  capture the reissue targets before they are touched
--   C  raise the generator from 32 bits to 192 bits
--   D  expire every valid unused invitation, legacy and 32-bit alike
--   E  create the replacements, secrets generated here rather than beforehand
--   F  apply the redemption, grant and map hardening
--   G  assert every post-condition, and commit only if all of them hold
--
-- Scope discipline. Hashed-only storage, anonymous abuse limiting, minimised
-- enumeration responses and retirement of the plaintext column remain Phase 2
-- and are documented in docs/P0_INVITATION_CONTAINMENT_PLAN.md. They are not in
-- this migration.
--
-- Any failure rolls the whole thing back and production is unchanged.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Baseline captured up front. Anything that must not change is measured before
-- anything changes, and asserted again at the end.
-- ---------------------------------------------------------------------------
create temp table p0_baseline on commit drop as
select
  (select count(*) from public.members)                                    as members,
  (select count(*) from public.admin_roles)                                as admin_roles,
  (select count(*) from public.invitation_codes where used_by is not null) as redeemed,
  (select count(*) from public.invitation_codes
     where used_by is null and expires_at > now())                         as valid_unused,
  (select count(*) from public.invitation_codes
     where used_by is null and expires_at > now()
       and recipient_email is not null)                                    as reissue_targets;

-- ---------------------------------------------------------------------------
-- A. Reversibility. The backup table is internal only: forced row level
--    security with no policy denies every role that is not the owner, and the
--    explicit revokes stop a future grant from quietly opening it.
-- ---------------------------------------------------------------------------
create table if not exists public.invitation_expiry_backup_20260921 (
  invitation_id    bigint primary key,
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
select id, expires_at, 'p0_containment_rev3'
from public.invitation_codes
where used_by is null and expires_at > now()
on conflict (invitation_id) do nothing;

-- ---------------------------------------------------------------------------
-- B. Capture the reissue targets before anything is expired. These are every
--    valid unused invitation addressed to a named person: the legacy ones about
--    to be retired, and the 32-bit ones that must not survive containment.
-- ---------------------------------------------------------------------------
create temp table p0_reissue_targets on commit drop as
select id as source_invitation_id, recipient_name, recipient_email, tier_grant
from public.invitation_codes
where used_by is null
  and expires_at > now()
  and recipient_email is not null;

-- ---------------------------------------------------------------------------
-- C. Raise the generator to 192 bits.
--
--    gen_random_bytes(24) is 24 bytes, which is 192 bits, hex encoded to 48
--    characters behind the existing readable prefix. The previous version used
--    gen_random_bytes(4), which is 32 bits.
--
--    Hex rather than a denser encoding because both client and server
--    upper-case the code before hashing, so the alphabet has to survive
--    upper-casing without losing entropy. Base64 would not. The cost is a long
--    code, acceptable for a value that is sent to be copied rather than typed
--    from memory. The client imposes no length or pattern constraint: verified
--    at app/(auth)/invite.tsx:44 and components/v2/Onboarding.tsx:308, which
--    check only a minimum of four characters.
-- ---------------------------------------------------------------------------
create or replace function public.generate_share_invite_code(p_prefix text default 'AMARI-INV')
returns text
language plpgsql
security definer
set search_path = public, extensions
as $gen$
declare
  v_candidate text;
begin
  loop
    v_candidate := upper(coalesce(p_prefix, 'AMARI-INV')) || '-'
                   || upper(encode(extensions.gen_random_bytes(24), 'hex'));
    exit when not exists (
      select 1 from public.invitation_codes where code = v_candidate
    );
  end loop;

  return v_candidate;
end;
$gen$;

revoke execute on function public.generate_share_invite_code(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- D. Expire every valid unused invitation.
--
--    Deliberately simpler than three overlapping predicates. The live baseline
--    showed 1,216 valid unused invitations: 1,210 legacy, predictable or
--    admin-capable rows, plus the six 32-bit survivors. Expiring the whole set
--    leaves nothing weak behind by construction, rather than by a pattern match
--    that might miss a shape nobody anticipated.
--
--    Nothing is deleted. Redeemed invitations are untouched. History intact.
-- ---------------------------------------------------------------------------
update public.invitation_codes
   set expires_at = now()
 where used_by is null
   and expires_at > now();

-- ---------------------------------------------------------------------------
-- E. Create the replacements, one per captured target, secrets generated here
--    inside the transaction rather than sitting valid beforehand.
-- ---------------------------------------------------------------------------
alter table public.invitation_codes
  drop constraint if exists invitation_codes_invite_source_check;
alter table public.invitation_codes
  add constraint invitation_codes_invite_source_check
  check (invite_source in ('bootstrap', 'monthly_member', 'admin', 'reissue'));

-- The identifiers are captured as the rows are written, so the assertions below
-- can speak about exactly the replacements this transaction created and nothing
-- else. Without this the checks scan every reissue row that has ever existed,
-- and a second run trips over the first run's rows once they have been expired
-- or redeemed.
create temp table p0_replacements on commit drop as
with inserted as (
  insert into public.invitation_codes (
    code, code_hash, code_prefix, invite_source,
    recipient_name, recipient_email, tier_grant,
    grants_admin, staff_role_grant, expires_at, issued_at
  )
  select
  gen.code,
  encode(extensions.digest(gen.code, 'sha256'), 'hex'),
  substring(gen.code, 1, 10),
  'reissue',
  t.recipient_name,
  t.recipient_email,
  t.tier_grant,
  false,
  null,
  now() + interval '90 days',
  now()
from p0_reissue_targets t
cross join lateral (
  select public.generate_share_invite_code(
    case t.tier_grant
      when 'laureate' then 'AMARI-LAUR'
      when 'platinum' then 'AMARI-PLAT'
      when 'gold'     then 'AMARI-GOLD'
      when 'silver'   then 'AMARI-SLVR'
      else 'AMARI-MEMB'
    end
    ) as code
  ) gen
  returning id
)
select id as invitation_id from inserted;

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

  -- An explicit allow-list rather than an ordered comparison. The enum does
  -- currently sort member < silver < gold < platinum < laureate, verified live,
  -- so `v_tier < 'gold'` would behave correctly today. It would stop behaving
  -- correctly the moment somebody adds a tier with a bare ALTER TYPE ADD VALUE,
  -- because a new label appends to the end of the sort order and would be
  -- treated as the highest tier in the system. The list below is the same rule
  -- with no dependency on enum ordering. The threshold is unchanged.
  if v_tier not in ('gold'::membership_tier,
                    'platinum'::membership_tier,
                    'laureate'::membership_tier) then
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
    -- An empty admin_roles means a freshly built database with no seed data,
    -- which is what CI and any new environment look like. There is nothing for
    -- the smoke test to exercise and no identity to borrow, so skip rather than
    -- raise. Wherever administrators exist, which includes production, the test
    -- below still runs and still fails the migration if the guard is wrong.
    raise notice 'no administrator present, skipping the map smoke test';
    return;
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
-- G. Every post-condition, asserted. The transaction commits only if all of
--    them hold. A partial result is not a possible outcome.
-- ---------------------------------------------------------------------------
do $assert$
declare
  b                 record;
  v_admin_capable   integer;
  v_bootstrap       integer;
  v_legacy_pattern  integer;
  v_weak_suffix     integer;
  v_replacements    integer;
  v_valid_unused    integer;
  v_bad_replacement integer;
  v_members         integer;
  v_admin_roles     integer;
  v_redeemed        integer;
begin
  select * into b from p0_baseline;

  select count(*) into v_admin_capable from public.invitation_codes
   where used_by is null and expires_at > now()
     and (coalesce(grants_admin, false) or staff_role_grant is not null);

  select count(*) into v_bootstrap from public.invitation_codes
   where used_by is null and expires_at > now() and invite_source = 'bootstrap';

  select count(*) into v_legacy_pattern from public.invitation_codes
   where used_by is null and expires_at > now()
     and coalesce(code, '') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$';

  -- Any surviving code whose random component is shorter than 40 hex
  -- characters, which catches the 32-bit suffixes and anything else weak.
  select count(*) into v_weak_suffix from public.invitation_codes
   where used_by is null and expires_at > now()
     and code is not null
     and length(code) - length(code_prefix) - 1 < 40;

  select count(*) into v_replacements
    from public.invitation_codes i
    join p0_replacements r on r.invitation_id = i.id
   where i.used_by is null and i.expires_at > now();

  select count(*) into v_valid_unused from public.invitation_codes
   where used_by is null and expires_at > now();

  -- A replacement that is wrong in any respect at all.
  select count(*) into v_bad_replacement
    from public.invitation_codes i
    join p0_replacements r on r.invitation_id = i.id
   where ( i.recipient_email is null
        or coalesce(i.grants_admin, false) is true
        or i.staff_role_grant is not null
        or i.used_by is not null
        or i.expires_at <= now()
        or i.code_hash is null
        or length(i.code) - length(i.code_prefix) - 1 <> 48 );

  select count(*) into v_members     from public.members;
  select count(*) into v_admin_roles from public.admin_roles;
  select count(*) into v_redeemed    from public.invitation_codes where used_by is not null;

  if v_admin_capable <> 0 then
    raise exception 'admin-capable invitations still valid and unused: %', v_admin_capable;
  end if;
  if v_bootstrap <> 0 then
    raise exception 'bootstrap invitations still valid and unused: %', v_bootstrap;
  end if;
  if v_legacy_pattern <> 0 then
    raise exception 'predictable legacy invitations still valid and unused: %', v_legacy_pattern;
  end if;
  if v_weak_suffix <> 0 then
    raise exception 'invitations with a weak random component still valid and unused: %', v_weak_suffix;
  end if;
  if v_replacements <> b.reissue_targets then
    raise exception 'expected % replacements, found %', b.reissue_targets, v_replacements;
  end if;
  if v_valid_unused <> b.reissue_targets then
    raise exception 'expected exactly % valid unused invitations after containment, found %',
      b.reissue_targets, v_valid_unused;
  end if;
  if v_bad_replacement <> 0 then
    raise exception 'replacements failing their own requirements: %', v_bad_replacement;
  end if;
  if v_members <> b.members then
    raise exception 'member count changed from % to %', b.members, v_members;
  end if;
  if v_admin_roles <> b.admin_roles then
    raise exception 'administrator count changed from % to %', b.admin_roles, v_admin_roles;
  end if;
  if v_redeemed <> b.redeemed then
    raise exception 'redeemed invitation count changed from % to %', b.redeemed, v_redeemed;
  end if;

  raise notice 'containment complete. % legacy invitations expired, % secure replacements created, % members and % administrators unchanged',
    b.valid_unused, v_replacements, v_members, v_admin_roles;
end;
$assert$;

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
