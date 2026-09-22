-- ============================================================================
-- Provision a shared reviewer account for external testing on iOS.
--
-- WHY THIS EXISTS
--
-- An external candidate under an Upwork trial should not have to hand over a
-- personal email address before a contract is agreed, and on iOS they do not
-- need to: the app is public on the App Store, and app/(auth)/invite.tsx already
-- ships a "Reviewer password access" mode that signs in with email and password
-- rather than an invitation code. This script prepares the member side of such
-- an account.
--
-- WHAT IT DOES NOT DO
--
-- It does not create the auth user and it never handles a password. Create the
-- auth user first in the Supabase dashboard, Authentication, Users, Add user,
-- with "Auto Confirm User" ticked, and set the password there. The password
-- then exists only in your hands and in Supabase, never in a transcript, a
-- command line or a log.
--
-- RUN
--   Dry run, which is the default and changes nothing:
--     psql -w -v ON_ERROR_STOP=1 -v email=reviewer1@amarigala.com \
--          -f scripts/reviewer-account-provision.sql
--
--   Apply:
--     psql -w -v ON_ERROR_STOP=1 -v email=reviewer1@amarigala.com \
--          -v tier=member -v days=14 -v dry_run=off \
--          -f scripts/reviewer-account-provision.sql
--
-- TIER, AND WHY THE DEFAULT IS THE LOW ONE
--
-- tier_level is member 1, silver 2, gold 3, platinum 4, laureate 5. Pulse
-- summary content needs 2 and full content needs 3. The Aligned directory and
-- the project map need gold and enforce it in the database after the P0
-- containment of 22 September 2026.
--
-- Gold would give a fuller review. It would also expose the names, employers
-- and project detail of 23 real members to somebody who is not yet under
-- contract. The default here is 'member' deliberately. Raise it only as a
-- decision you have actually made.
--
-- REVOKING
--   scripts/external-tester-revoke.sql, which suspends the member so the
--   database refuses them rather than the app merely hiding things. Rotate the
--   password in the Supabase dashboard at the same time, because a shared
--   credential may have been passed on.
-- ============================================================================

\set ON_ERROR_STOP on
\if :{?email} \else \echo 'ERROR: pass -v email=...' \quit 1 \endif
\if :{?tier}    \else \set tier member \endif
\if :{?days}    \else \set days 14 \endif
\if :{?dry_run} \else \set dry_run on \endif

begin;

select set_config('request.jwt.claim.role', 'service_role', true);

create temp table reviewer_ctx on commit drop as
select lower(btrim(:'email'))     as email,
       (:'tier')::membership_tier as tier,
       (:'days')::integer         as access_days;

-- ---------------------------------------------------------------------------
-- Preconditions. Fail before writing anything.
--
-- Note for future edits: psql does not substitute :variables inside a
-- dollar-quoted block, which is why everything below reads from reviewer_ctx.
-- ---------------------------------------------------------------------------
do $check$
declare
  v_email     text;
  v_tier      membership_tier;
  v_uid       uuid;
  v_confirmed timestamptz;
  v_is_admin  integer;
  v_existing  integer;
begin
  select email, tier into v_email, v_tier from reviewer_ctx;

  select u.id, u.email_confirmed_at into v_uid, v_confirmed
    from auth.users u where lower(u.email) = v_email;

  if v_uid is null then
    raise exception
      'No auth user for %. Create it first in the Supabase dashboard, Authentication, Users, Add user, with Auto Confirm User ticked.',
      v_email;
  end if;

  if v_confirmed is null then
    raise exception
      'Auth user % exists but the email is not confirmed. Password sign-in is refused until it is.',
      v_email;
  end if;

  -- A reviewer account must never be admin capable. Checked, not assumed.
  select count(*) into v_is_admin from public.admin_roles where user_id = v_uid;
  if v_is_admin > 0 then
    raise exception 'Refusing: % holds an admin role.', v_email;
  end if;

  if v_tier in ('platinum'::membership_tier, 'laureate'::membership_tier) then
    raise exception 'Refusing tier % for a reviewer account.', v_tier;
  end if;

  select count(*) into v_existing from public.members where id = v_uid and status = 'active';
  if v_existing > 0 then
    raise notice 'NOTE: % already has an active member row. It will be re-pointed at tier %.', v_email, v_tier;
  end if;

  raise notice 'Preconditions passed for % at tier %.', v_email, v_tier;
end;
$check$;

-- ---------------------------------------------------------------------------
-- The member row.
-- ---------------------------------------------------------------------------
insert into public.members (id, display_id, tier, status, full_name, email, onboarded_at, consent_given_at)
select u.id,
       public.generate_display_id(),
       c.tier,
       'active'::member_status,
       'AMARI Reviewer',
       c.email,
       now(),
       now()
  from reviewer_ctx c
  join auth.users u on lower(u.email) = c.email
on conflict (id) do update
  set tier   = excluded.tier,
      status = 'active'::member_status,
      email  = excluded.email;

-- ---------------------------------------------------------------------------
-- Tracking, so ending access is a query rather than an act of memory. Skipped
-- cleanly if the tracking migration has not been applied yet.
-- ---------------------------------------------------------------------------
do $track$
declare
  v_uid   uuid;
  v_email text;
  v_tier  membership_tier;
  v_days  integer;
begin
  if to_regclass('public.external_tester_access') is null then
    raise notice 'SKIPPED tracking row: external_tester_access does not exist. Apply supabase/migrations/20260922000001_external_tester_access.sql to make revoking reliable.';
    return;
  end if;

  select c.email, c.tier, c.access_days into v_email, v_tier, v_days from reviewer_ctx c;
  select u.id into v_uid from auth.users u where lower(u.email) = v_email;

  if exists (select 1 from public.external_tester_access
              where lower(tester_email) = v_email and revoked_at is null) then
    raise notice 'Tracking row already open for %.', v_email;
    return;
  end if;

  execute format(
    'insert into public.external_tester_access
       (tester_name, tester_email, platform, intended_tier, member_id, access_expires_at, notes)
     values (%L, %L, %L, %L, %L, %L, %L)',
    'AMARI Reviewer', v_email, 'ios', v_tier, v_uid,
    now() + (v_days || ' days')::interval,
    'shared reviewer password account, Upwork trial, no tester email required');
end;
$track$;

\echo ''
\echo '=== Reviewer account state (no secrets) ==='
select m.email,
       m.display_id,
       m.tier::text   as tier,
       m.status::text as status,
       (select count(*) from public.admin_roles a where a.user_id = m.id) as admin_roles,
       public.tier_level(m.tier) as tier_level
  from public.members m
  join reviewer_ctx c on lower(m.email) = c.email;

-- ---------------------------------------------------------------------------
-- Fail closed.
-- ---------------------------------------------------------------------------
do $verify$
declare
  v_email   text;
  v_status  text;
  v_admin   integer;
  v_members integer;
begin
  select email into v_email from reviewer_ctx;

  select m.status::text, (select count(*) from public.admin_roles a where a.user_id = m.id)
    into v_status, v_admin
    from public.members m where lower(m.email) = v_email;

  if v_status is distinct from 'active' then
    raise exception 'reviewer member row is % rather than active', coalesce(v_status, 'missing');
  end if;
  if v_admin <> 0 then
    raise exception 'reviewer account acquired % admin role(s)', v_admin;
  end if;

  -- Nothing else about membership may move. 23 real members plus reviewers.
  select count(*) into v_members from public.members;
  if v_members > 25 then
    raise exception 'member count is %, which is more than this script should ever produce', v_members;
  end if;

  raise notice 'verified: % is an active reviewer member with no admin role', v_email;
end;
$verify$;

\if :dry_run
  \echo ''
  \echo '*** DRY RUN. Rolled back, nothing changed. Re-run with -v dry_run=off to apply. ***'
  rollback;
\else
  commit;
\endif
