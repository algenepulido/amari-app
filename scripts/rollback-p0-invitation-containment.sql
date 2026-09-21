-- ============================================================================
-- Rollback for 20260921000001_p0_invitation_containment.sql
--
-- Four independent sections. Run only the section you need. In almost every
-- realistic failure the answer is section 2 alone, because a grant is what
-- would break a client, not the function body.
--
-- Section 3 deliberately restores the vulnerable definition of
-- redeem_invitation_code. It exists so that rollback is genuinely complete, not
-- because restoring it is ever a good idea. Read the warning before running it.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- SECTION 1. Restore the exact previous expiry of every invitation the
-- containment migration expired. Uses the values captured at the time, not an
-- approximation, and refuses to touch anything that has since been redeemed.
-- ---------------------------------------------------------------------------
begin;

update public.invitation_codes i
   set expires_at = b.previous_expires
  from public.invitation_expiry_backup_20260921 b
 where b.invitation_id = i.id
   and b.reason = 'p0_containment_rev3'
   and i.used_by is null;

-- Report, do not assume.
do $verify$
declare
  v_restored integer;
begin
  select count(*) into v_restored
  from public.invitation_codes i
  join public.invitation_expiry_backup_20260921 b on b.invitation_id = i.id
  where i.expires_at = b.previous_expires;
  raise notice 'rollback section 1 restored % invitation expiries', v_restored;
end;
$verify$;

commit;


-- ---------------------------------------------------------------------------
-- SECTION 2. Restore the previous EXECUTE grants.
--
-- This is the section that matters if a client breaks. It returns every
-- affected function to the grant state captured in
-- docs/evidence/live-verification-baseline-20260921.csv.
-- ---------------------------------------------------------------------------
begin;

grant execute on function public.redeem_invitation_code(text, uuid, text, text, text, text)
  to public, anon, authenticated;

grant execute on function public.cleanup_rate_limits()
  to public, anon, authenticated;

grant execute on function public.check_rate_limit(text, text, integer, integer)
  to public, anon, authenticated;

grant execute on function public.map_projects(
  double precision, double precision, double precision, double precision, text)
  to public, anon, authenticated;

grant execute on function public.map_states(
  double precision, double precision, double precision, double precision, text)
  to public, anon, authenticated;

grant execute on function public.map_countries(text)
  to public, anon, authenticated;

commit;


-- ---------------------------------------------------------------------------
-- SECTION 3. Remove the fixed search_path from the three map functions,
-- returning them to having none. Only needed if the fixed path turns out to
-- break something the smoke test did not cover.
-- ---------------------------------------------------------------------------
begin;

alter function public.map_projects(
  double precision, double precision, double precision, double precision, text)
  reset search_path;
alter function public.map_states(
  double precision, double precision, double precision, double precision, text)
  reset search_path;
alter function public.map_countries(text) reset search_path;

commit;


-- ---------------------------------------------------------------------------
-- SECTION 4. Restore the default privilege behaviour for newly created
-- functions in the application schema.
-- ---------------------------------------------------------------------------
begin;

alter default privileges for role postgres in schema public
  grant execute on functions to public;

commit;


-- ---------------------------------------------------------------------------
-- SECTION 5. Restore the PREVIOUS, VULNERABLE definition of
-- redeem_invitation_code.
--
-- WARNING. This reinstates a function that accepts a caller-supplied user
-- identifier without comparing it to auth.uid(). Combined with section 2 it
-- restores the exposure this work was undertaken to close. It is here so that
-- rollback is complete and honest, and it should not be run unless the
-- hardened definition is proven to break something that cannot be fixed
-- forward.
-- ---------------------------------------------------------------------------
begin;

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
  v_invite public.invitation_codes%rowtype;
  v_member_exists boolean;
  v_existing_member_id uuid;
  v_hash text;
  v_is_staff boolean;
  v_admin_role text;
  v_normalized_email text;
  v_member_email text;
begin
  select exists (
    select 1
    from public.members
    where id = p_user_id
  )
  into v_member_exists;

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
    p_user_id,
    p_full_name,
    v_member_email,
    v_invite.tier_grant,
    'active',
    p_city,
    p_industry
  );

  v_admin_role := coalesce(v_invite.staff_role_grant, case when v_invite.grants_admin then 'admin' else null end);
  v_is_staff := v_admin_role is not null;

  if v_is_staff then
    insert into public.admin_roles (member_id, role)
    values (p_user_id, v_admin_role)
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
  where id = p_user_id;

  update public.invitation_codes
  set used_by = p_user_id,
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

commit;
