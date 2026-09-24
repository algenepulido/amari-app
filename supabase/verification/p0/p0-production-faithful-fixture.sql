-- ============================================================================
-- Production-faithful fixture, revision 3.
--
-- Rebuilt from the repository DDL, which was previously proven byte-identical
-- to production for every function in scope, and cross-checked against the
-- read-only production metadata captured on 21 September.
--
-- Two earlier fixtures hid real defects by diverging from production: one
-- declared invitation_codes.id as uuid when production has bigint, and one
-- omitted the members display_id trigger entirely. This one reproduces the
-- structure that matters to behaviour, including identity columns, NOT NULL
-- constraints, foreign keys, triggers, enum value order, RLS state and the
-- pre-migration privilege topology.
--
-- Synthetic rows only. No production data.
-- ============================================================================

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create schema extensions;
create extension if not exists pgcrypto with schema extensions;
-- PostGIS stand-in. The host lacks the memory to run a PostGIS container
-- alongside the other work on this machine, so the geometry type and the four
-- spatial functions used by the map queries are substituted. They live in the
-- extensions schema so that the migration's fixed search_path of
-- "public, extensions" is still genuinely exercised. Recorded as a known gap in
-- docs/P0_FIXTURE_FIDELITY_MANIFEST.md: it affects spatial evaluation only, not
-- the grants, tier gating or invitation lifecycle under test.
create domain extensions.geometry as text;
create function extensions.st_y(extensions.geometry) returns double precision
  language sql immutable as $sg$ select 0::double precision $sg$;
create function extensions.st_x(extensions.geometry) returns double precision
  language sql immutable as $sg$ select 0::double precision $sg$;
create function extensions.st_makepoint(double precision, double precision)
  returns extensions.geometry language sql immutable as $sg$ select 'pt'::extensions.geometry $sg$;
create function extensions.st_setsrid(extensions.geometry, integer)
  returns extensions.geometry language sql immutable as $sg$ select $1 $sg$;
create function extensions.st_makeenvelope(double precision, double precision,
  double precision, double precision, integer) returns extensions.geometry
  language sql immutable as $sg$ select 'env'::extensions.geometry $sg$;
create function extensions.st_intersects(extensions.geometry, extensions.geometry)
  returns boolean language sql immutable as $sg$ select true $sg$;

set search_path = public, extensions;

-- --------------------------------------------------------------------------
-- auth, as Supabase provides it to the parts we touch
-- --------------------------------------------------------------------------
create schema auth;
create table auth.users (
  id uuid primary key,
  raw_app_meta_data jsonb
);

create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), current_user::text)
$$;

-- --------------------------------------------------------------------------
-- Enums, exact production values and order
-- --------------------------------------------------------------------------
create type membership_tier as enum ('member', 'silver', 'platinum', 'laureate');
alter type membership_tier add value 'gold' before 'platinum';
create type member_status as enum ('pending', 'active', 'suspended', 'inactive');
create type project_category as enum ('energy', 'health', 'education', 'finance', 'other');

-- --------------------------------------------------------------------------
-- members
-- --------------------------------------------------------------------------
create table members (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_id    text unique not null,
  tier          membership_tier not null default 'member',
  status        member_status not null default 'pending',
  full_name     text not null,
  email         text not null,
  photo_url     text,
  bio           text,
  industry      text,
  city          text,
  company       text,
  title         text,
  onboarded_at  timestamptz,
  invited_by    uuid references members(id),
  created_at    timestamptz default now()
);

create or replace function generate_display_id() returns text
language sql volatile as $$
  select 'AM-' || upper(encode(extensions.gen_random_bytes(4), 'hex'))
$$;

create or replace function set_member_display_id() returns trigger
language plpgsql as $$
begin
  if new.display_id is null then
    new.display_id := generate_display_id();
  end if;
  return new;
end;
$$;

create trigger tr_member_display_id
  before insert on members
  for each row execute function set_member_display_id();

alter table members enable row level security;
create policy members_self_read on members for select to authenticated using (id = auth.uid());
create policy members_self_profile_update on members for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- --------------------------------------------------------------------------
-- admin_roles
-- --------------------------------------------------------------------------
create table admin_roles (
  member_id  uuid primary key references members(id),
  role       text not null check (role in ('owner', 'admin', 'editor', 'door_staff')),
  granted_by uuid references members(id),
  created_at timestamptz default now()
);
alter table admin_roles enable row level security;

-- --------------------------------------------------------------------------
-- invitation_codes, base plus every later alter that matters
-- --------------------------------------------------------------------------
create table invitation_codes (
  id          bigint generated always as identity primary key,
  code        text unique not null,
  created_by  uuid references members(id),
  used_by     uuid references members(id),
  tier_grant  membership_tier default 'member',
  expires_at  timestamptz not null,
  used_at     timestamptz,
  created_at  timestamptz default now()
);

alter table invitation_codes
  add column grants_admin boolean not null default false,
  add column code_hash text,
  add column code_prefix text,
  add column staff_role_grant text,
  add column invite_source text not null default 'bootstrap',
  add column issued_by uuid references members(id),
  add column issued_at timestamptz,
  add column issued_month date,
  add column recipient_name text,
  add column recipient_email text;

alter table invitation_codes
  add constraint invitation_codes_invite_source_check
  check (invite_source in ('bootstrap', 'monthly_member', 'admin'));

alter table invitation_codes enable row level security;

-- --------------------------------------------------------------------------
-- rate_limits: ip_address, not key
-- --------------------------------------------------------------------------
create table rate_limits (
  id         bigint generated always as identity primary key,
  ip_address text not null,
  endpoint   text not null,
  created_at timestamptz default now()
);
alter table rate_limits enable row level security;
grant select, insert, delete on rate_limits to anon, authenticated;

-- --------------------------------------------------------------------------
-- projects and the map cache, with real PostGIS geometry
-- --------------------------------------------------------------------------
create table projects (
  id uuid primary key default gen_random_uuid(),
  name text not null
);

create table map_cache_countries (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  country_name text not null,
  project_count integer not null,
  categories jsonb not null default '{}',
  centroid extensions.geometry not null,
  refreshed_at timestamptz not null default now()
);

create table map_cache_states (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  state_province text not null,
  display_label text not null,
  project_count integer not null,
  categories jsonb not null default '{}',
  centroid extensions.geometry not null,
  refreshed_at timestamptz not null default now()
);

create table map_cache_projects (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  description text not null,
  category project_category not null,
  creator_first_name text not null,
  display_label text not null,
  image_url text,
  external_link text,
  display_point extensions.geometry not null,
  refreshed_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------
-- Pre-existing functions, production definitions and privilege topology.
-- CREATE OR REPLACE behaves differently on an existing function than on a new
-- one, so the migration must meet the same starting ACLs production has.
-- --------------------------------------------------------------------------
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_roles where member_id = auth.uid());
$$;

create or replace function is_active_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where id = auth.uid() and status = 'active');
$$;

create or replace function get_member_tier() returns membership_tier
language plpgsql stable security definer set search_path = public as $$
declare v_tier membership_tier;
begin
  select tier into v_tier from public.members where id = auth.uid() and status = 'active';
  if v_tier is not null then return v_tier; end if;
  return 'member'::membership_tier;
end;
$$;

create or replace function check_rate_limit(p_ip text, p_endpoint text,
  p_max_requests integer, p_window_minutes integer)
returns boolean language plpgsql security definer as $$
declare v_count integer;
begin
  select count(*) into v_count from public.rate_limits
   where ip_address = p_ip and endpoint = p_endpoint
     and created_at > now() - (p_window_minutes || ' minutes')::interval;
  if v_count >= p_max_requests then return false; end if;
  insert into public.rate_limits (ip_address, endpoint) values (p_ip, p_endpoint);
  return true;
end;
$$;

create or replace function cleanup_rate_limits() returns void language sql as $$
  delete from public.rate_limits where created_at < now() - interval '1 day'
$$;

create or replace function generate_share_invite_code(p_prefix text default 'AMARI-INV')
returns text language plpgsql security definer set search_path = public, extensions as $gen$
declare v_candidate text;
begin
  loop
    v_candidate := upper(coalesce(p_prefix, 'AMARI-INV')) || '-' ||
                   substring(encode(extensions.gen_random_bytes(4), 'hex') from 1 for 8);
    exit when not exists (select 1 from public.invitation_codes where code = v_candidate);
  end loop;
  return v_candidate;
end; $gen$;
revoke execute on function generate_share_invite_code(text) from public, anon, authenticated;

create or replace function validate_invitation_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $v$
declare v_hash text; v_exists boolean;
begin
  if p_code is null or btrim(p_code) = '' then return jsonb_build_object('valid', false); end if;
  v_hash := encode(extensions.digest(upper(btrim(p_code)), 'sha256'), 'hex');
  select exists (select 1 from public.invitation_codes
    where code_hash = v_hash and used_by is null and expires_at > now()) into v_exists;
  return jsonb_build_object('valid', v_exists);
end; $v$;
revoke execute on function validate_invitation_code(text) from public;
grant execute on function validate_invitation_code(text) to anon, authenticated;

-- The pre-migration, vulnerable redemption function, exactly as production has it.
create or replace function redeem_invitation_code(
  p_code text, p_user_id uuid, p_full_name text, p_email text,
  p_city text default null, p_industry text default null)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  v_invite public.invitation_codes%rowtype;
  v_member_exists boolean;
  v_existing_member_id uuid;
  v_hash text;
  v_is_staff boolean;
  v_admin_role text;
  v_normalized_email text;
  v_member_email text;
begin
  select exists (select 1 from public.members where id = p_user_id) into v_member_exists;
  if v_member_exists then
    return jsonb_build_object('success', false, 'error', 'already_member');
  end if;

  v_hash := encode(extensions.digest(upper(p_code), 'sha256'), 'hex');

  select * into v_invite from public.invitation_codes
   where code_hash = v_hash and used_by is null and expires_at > now()
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

  select id into v_existing_member_id from public.members
   where lower(btrim(email)) = v_member_email and status in ('active','pending')
   order by created_at asc limit 1;
  if v_existing_member_id is not null then
    update public.invitation_codes set used_by = v_existing_member_id,
           used_at = coalesce(used_at, now())
     where id = v_invite.id and used_by is null;
    return jsonb_build_object('success', false, 'error', 'already_member');
  end if;

  insert into public.members (id, full_name, email, tier, status, city, industry)
  values (p_user_id, p_full_name, v_member_email, v_invite.tier_grant, 'active', p_city, p_industry);

  v_admin_role := coalesce(v_invite.staff_role_grant,
                           case when v_invite.grants_admin then 'admin' else null end);
  v_is_staff := v_admin_role is not null;
  if v_is_staff then
    insert into public.admin_roles (member_id, role) values (p_user_id, v_admin_role)
    on conflict (member_id) do update set role = excluded.role;
  end if;

  update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) ||
    jsonb_build_object('tier', v_invite.tier_grant::text, 'is_admin', v_is_staff,
                       'admin_role', v_admin_role)
   where id = p_user_id;

  update public.invitation_codes set used_by = p_user_id, used_at = now()
   where id = v_invite.id;

  return jsonb_build_object('success', true, 'tier', v_invite.tier_grant::text,
                            'is_admin', v_is_staff, 'admin_role', v_admin_role);
end; $fn$;
grant execute on function redeem_invitation_code(text, uuid, text, text, text, text) to authenticated;

-- Pre-migration map functions, production definitions.
create or replace function map_countries(category_filter text default null)
returns table (country_code text, country_name text, project_count integer,
  categories jsonb, lat double precision, lng double precision)
language sql stable security definer as $$
  select country_code, country_name, project_count, categories,
         extensions.ST_Y(centroid), extensions.ST_X(centroid)
  from public.map_cache_countries
  where (category_filter is null or categories ? category_filter);
$$;

create or replace function map_states(min_lat double precision, min_lng double precision,
  max_lat double precision, max_lng double precision, category_filter text default null)
returns table (state_province text, display_label text, project_count integer,
  categories jsonb, lat double precision, lng double precision)
language sql stable security definer as $$
  select state_province, display_label, project_count, categories,
         extensions.ST_Y(centroid), extensions.ST_X(centroid)
  from public.map_cache_states
  where extensions.ST_Intersects(centroid,
          extensions.ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326))
    and (category_filter is null or categories ? category_filter);
$$;

create or replace function map_projects(min_lat double precision, min_lng double precision,
  max_lat double precision, max_lng double precision, category_filter text default null)
returns table (project_id uuid, name text, description text, category text,
  creator_first_name text, display_label text, image_url text, external_link text,
  lat double precision, lng double precision)
language sql stable security definer as $$
  select project_id, name, description, category::text, creator_first_name, display_label,
         image_url, external_link,
         extensions.ST_Y(display_point), extensions.ST_X(display_point)
  from public.map_cache_projects
  where extensions.ST_Intersects(display_point,
          extensions.ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326))
    and (category_filter is null or category::text = category_filter);
$$;

-- --------------------------------------------------------------------------
-- Synthetic data. One identity per tier, plus suspended, inactive, admin and
-- a non-member. No production data.
-- --------------------------------------------------------------------------
insert into auth.users (id, raw_app_meta_data) values
  ('00000000-0000-0000-0000-000000000001', '{}'),
  ('00000000-0000-0000-0000-000000000002', '{}'),
  ('00000000-0000-0000-0000-000000000003', '{}'),
  ('00000000-0000-0000-0000-000000000004', '{}'),
  ('00000000-0000-0000-0000-000000000005', '{}'),
  ('00000000-0000-0000-0000-000000000006', '{}'),
  ('00000000-0000-0000-0000-000000000007', '{}'),
  ('00000000-0000-0000-0000-000000000008', '{}'),
  ('00000000-0000-0000-0000-000000000009', '{}');

insert into members (id, full_name, email, tier, status) values
  ('00000000-0000-0000-0000-000000000001', 'Fixture Member',    'member@example.invalid',    'member',   'active'),
  ('00000000-0000-0000-0000-000000000002', 'Fixture Silver',    'silver@example.invalid',    'silver',   'active'),
  ('00000000-0000-0000-0000-000000000003', 'Fixture Gold',      'gold@example.invalid',      'gold',     'active'),
  ('00000000-0000-0000-0000-000000000004', 'Fixture Platinum',  'platinum@example.invalid',  'platinum', 'active'),
  ('00000000-0000-0000-0000-000000000005', 'Fixture Laureate',  'laureate@example.invalid',  'laureate', 'active'),
  ('00000000-0000-0000-0000-000000000006', 'Fixture Suspended', 'suspended@example.invalid', 'gold',     'suspended'),
  ('00000000-0000-0000-0000-000000000007', 'Fixture Inactive',  'inactive@example.invalid',  'gold',     'inactive'),
  ('00000000-0000-0000-0000-000000000008', 'Fixture Admin',     'admin@example.invalid',     'member',   'active');
-- identity 9 is deliberately NOT a member

insert into admin_roles (member_id, role)
values ('00000000-0000-0000-0000-000000000008', 'admin');

insert into projects (id, name) values
  ('00000000-0000-0000-0000-0000000000f1', 'Fixture Project');

insert into map_cache_countries (country_code, country_name, project_count, categories, centroid)
values ('AU', 'Australia', 1, '["energy"]'::jsonb,
        extensions.ST_SetSRID(extensions.ST_MakePoint(133.0, -25.0), 4326));

insert into map_cache_states (country_code, state_province, display_label, project_count, categories, centroid)
values ('AU', 'NSW', 'New South Wales', 1, '["energy"]'::jsonb,
        extensions.ST_SetSRID(extensions.ST_MakePoint(147.0, -32.0), 4326));

insert into map_cache_projects (project_id, name, description, category, creator_first_name,
  display_label, display_point)
values ('00000000-0000-0000-0000-0000000000f1', 'Fixture Project', 'A synthetic project',
        'energy', 'Ada', 'Sydney',
        extensions.ST_SetSRID(extensions.ST_MakePoint(151.2, -33.8), 4326));

-- Invitation shapes that matter: admin-capable, predictable legacy, a weak
-- 32-bit addressed code, and one already redeemed.
insert into invitation_codes
  (code, code_hash, code_prefix, expires_at, tier_grant, grants_admin, staff_role_grant,
   invite_source, recipient_name, recipient_email)
values
  ('AMARI-OWNR-001', encode(extensions.digest('AMARI-OWNR-001','sha256'),'hex'), 'AMARI-OWNR',
   now() + interval '180 days', 'laureate', true, 'owner', 'bootstrap', null, null),
  ('AMARI-MEMB-001', encode(extensions.digest('AMARI-MEMB-001','sha256'),'hex'), 'AMARI-MEMB',
   now() + interval '180 days', 'member', false, null, 'bootstrap', null, null),
  ('AMARI-PLAT-014', encode(extensions.digest('AMARI-PLAT-014','sha256'),'hex'), 'AMARI-PLAT',
   now() + interval '180 days', 'platinum', false, null, 'bootstrap', 'Legacy Person',
   'legacy.addressed@example.invalid'),
  ('AMARI-SLVR-A3B44BDA', encode(extensions.digest('AMARI-SLVR-A3B44BDA','sha256'),'hex'), 'AMARI-SLVR',
   now() + interval '90 days', 'silver', false, null, 'admin', 'Weak Code Person',
   'weak.addressed@example.invalid');

insert into invitation_codes
  (code, code_hash, code_prefix, expires_at, tier_grant, grants_admin, invite_source,
   used_by, used_at)
values
  ('AMARI-ADMN-USED', encode(extensions.digest('AMARI-ADMN-USED','sha256'),'hex'), 'AMARI-ADMN',
   now() + interval '180 days', 'laureate', true, 'bootstrap',
   '00000000-0000-0000-0000-000000000001', now());
