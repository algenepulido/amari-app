-- ============================================================================
-- P0 invitation containment
--
-- PROPOSED. NOT APPLIED. Requires explicit approval before execution.
--
-- Closes the exposure verified live on 21 September 2026:
--   nine valid unused admin-capable invitation codes, eight of them in the
--   predictable published bootstrap format, combined with a redemption
--   function executable by PUBLIC and anon that trusts a caller-supplied
--   user identifier.
--
-- Scope discipline. This migration does the minimum needed to close the
-- confirmed exposure. It does not touch unrelated product functionality, it
-- does not mass-revoke EXECUTE across the schema, it deletes nothing, and it
-- does not alter any already redeemed invitation.
--
-- Deliberately NOT included, and documented in
-- docs/P0_INVITATION_CONTAINMENT_PLAN.md:
--   * the 1,206 unaddressed predictable bootstrap codes, which need a decision
--     because three sibling codes are addressed to named people;
--   * the Apple private relay email bypass in redemption;
--   * retiring plaintext code storage;
--   * an allow-list pass over the remaining functions holding a PUBLIC grant.
--
-- Everything here runs in one transaction. Any failure rolls the whole thing
-- back and production is unchanged.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Reversibility. Capture the prior expiry of every row this migration will
--    expire, so rollback can restore the exact previous values rather than an
--    approximation.
-- ---------------------------------------------------------------------------
create table if not exists public.invitation_expiry_backup_20260921 (
  invitation_id    uuid primary key,
  previous_expires timestamptz not null,
  backed_up_at     timestamptz not null default now(),
  reason           text not null
);

alter table public.invitation_expiry_backup_20260921 enable row level security;
revoke all on table public.invitation_expiry_backup_20260921 from public, anon, authenticated;
grant select, insert on table public.invitation_expiry_backup_20260921 to service_role;

insert into public.invitation_expiry_backup_20260921 (invitation_id, previous_expires, reason)
select id, expires_at, 'p0_admin_capable_containment'
from public.invitation_codes
where used_by is null
  and expires_at > now()
  and (coalesce(grants_admin, false) or staff_role_grant is not null)
on conflict (invitation_id) do nothing;

-- ---------------------------------------------------------------------------
-- A. Expire every valid unused admin-capable invitation.
--    No row is deleted. Redeemed invitations are untouched. History is intact.
--    Verified before writing this: none of these rows is addressed to a named
--    recipient, so no individual's pending onboarding is affected.
-- ---------------------------------------------------------------------------
update public.invitation_codes
   set expires_at = now()
 where used_by is null
   and expires_at > now()
   and (coalesce(grants_admin, false) or staff_role_grant is not null);

-- Fail closed. The migration aborts unless the objective is actually met.
do $guard$
declare
  v_remaining integer;
begin
  select count(*) into v_remaining
  from public.invitation_codes
  where used_by is null
    and expires_at > now()
    and (coalesce(grants_admin, false) or staff_role_grant is not null);

  if v_remaining <> 0 then
    raise exception
      'containment objective not met: % admin-capable invitations remain valid and unused',
      v_remaining;
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------------
-- C. Redemption becomes authenticated-only and binds to auth.uid().
--
--    The product already redeems only after sign-in. providers/AuthProvider.tsx
--    guards on an established session and passes the signed-in user's own id,
--    so binding to auth.uid() is compatible with the shipped client and with
--    every build currently in the field.
--
--    The signature is deliberately unchanged so that existing clients continue
--    to work. p_user_id is now validated rather than trusted, and is ignored in
--    favour of auth.uid().
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
  -- Fail closed when there is no authenticated caller.
  if v_actor is null then
    return jsonb_build_object('success', false, 'error', 'not_authenticated');
  end if;

  -- Never act on behalf of another identity. The caller may pass its own id or
  -- nothing at all; anything else is refused.
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
-- D. Rate limit plumbing becomes internal only.
--
--    Neither function has a client call site anywhere in the application.
--    check_rate_limit is reachable from inside SECURITY DEFINER functions
--    regardless of the caller's own privileges, so revoking it does not break
--    any server-side use.
--
--    cleanup_rate_limits being anon-callable is what would let a caller clear
--    its own throttle, so this is a precondition for rate limiting to mean
--    anything at all.
-- ---------------------------------------------------------------------------
revoke execute on function public.cleanup_rate_limits()
  from public, anon, authenticated;
grant execute on function public.cleanup_rate_limits() to service_role;

revoke execute on function public.check_rate_limit(text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.check_rate_limit(text, text, integer, integer) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Map functions become member-only.
--
--    They are consumed solely by app/(tabs)/aligned/index.tsx and
--    components/aligned/ProjectMap.tsx, both behind the Aligned tab, so no
--    anonymous caller has a legitimate need for them. They return project
--    name, description, category, creator first name, image, link and
--    coordinates, which is member-facing content.
--
--    A fixed search_path is set because all three are SECURITY DEFINER and
--    currently have none. PostGIS is not created by any migration in this
--    repository, so its schema is not known from source. The smoke test below
--    proves the new search_path resolves the PostGIS operators before this
--    transaction is allowed to commit.
-- ---------------------------------------------------------------------------
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

alter function public.map_projects(
  double precision, double precision, double precision, double precision, text)
  set search_path = public, extensions;
alter function public.map_states(
  double precision, double precision, double precision, double precision, text)
  set search_path = public, extensions;
alter function public.map_countries(text)
  set search_path = public, extensions;

-- Smoke test. If the fixed search_path cannot resolve PostGIS, this raises and
-- the entire migration rolls back, leaving production exactly as it was.
do $smoke$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.map_projects(-90.0, -180.0, 90.0, 180.0, null);
  raise notice 'map_projects smoke test returned % rows', v_count;

  select count(*) into v_count
  from public.map_states(-90.0, -180.0, 90.0, 180.0, null);
  raise notice 'map_states smoke test returned % rows', v_count;

  select count(*) into v_count
  from public.map_countries(null);
  raise notice 'map_countries smoke test returned % rows', v_count;
exception
  when others then
    raise exception
      'map function smoke test failed under the fixed search_path: %', sqlerrm;
end;
$smoke$;

-- ---------------------------------------------------------------------------
-- 4. Stop the pattern recurring for functions created from here on.
--
--    This changes the default for NEW functions only. It does not touch any
--    existing function, which is deliberate: a mass revoke would break the live
--    application. The existing PUBLIC grants are retired separately through a
--    reviewed allow-list.
--
--    CREATE OR REPLACE on an existing function preserves that function's
--    current ACL, so this default is not silently undone by later edits.
-- ---------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke execute on functions from public;

commit;
