-- HO-05: prove invitation ownership from the authenticated identity, not a client-supplied
-- email. The previous version matched a named code's recipient_email against p_email, a value
-- the app passes, so three things were possible:
--   1. a different authenticated account could redeem someone else's named code by supplying
--      the recipient's email as p_email;
--   2. any Apple private-relay address bypassed the recipient check through the relay carve-out;
--   3. an open code could be consumed under an existing member's email, marking it used without
--      creating the intended new membership.
-- This recreates redeem_invitation_code so the recipient match and the new member email come
-- from the caller's verified email on auth.users, never from p_email. p_email stays in the
-- signature for compatibility but no longer proves ownership of anything.
--
-- Apple Hide My Email: a named code now requires the verified email to equal the recipient, so
-- a relay address cannot take a named invite. Genuine relay sign-ups go through open codes,
-- which carry no named recipient and are bearer by design. Applies after 20261008000002.

create or replace function public.redeem_invitation_code(p_code text, p_user_id uuid, p_full_name text, p_email text, p_city text default null::text, p_industry text default null::text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  c_per_caller_max    constant integer := 10;
  c_per_caller_window constant interval := interval '10 minutes';
  c_global_max        constant integer := 120;
  c_global_window     constant interval := interval '1 minute';
  v_actor uuid := auth.uid();
  v_invite public.invitation_codes%rowtype;
  v_member_exists boolean;
  v_existing_member_id uuid;
  v_hash text;
  v_is_staff boolean;
  v_admin_role text;
  v_verified_email text;
  v_member_email text;
  v_count integer;
begin
  if v_actor is null then
    return jsonb_build_object('success', false, 'error', 'not_authenticated');
  end if;

  if p_user_id is not null and p_user_id <> v_actor then
    return jsonb_build_object('success', false, 'error', 'identity_mismatch');
  end if;

  -- HO-05: ownership is proven by the caller's verified email on auth.users, never by the
  -- p_email the app passes. p_email is ignored for every security decision below.
  select lower(btrim(email)) into v_verified_email from auth.users where id = v_actor;
  if v_verified_email is null or v_verified_email = '' then
    return jsonb_build_object('success', false, 'error', 'no_verified_email');
  end if;

  select exists (select 1 from public.members where id = v_actor) into v_member_exists;
  if v_member_exists then
    return jsonb_build_object('success', false, 'error', 'already_member');
  end if;

  -- HO-04 atomic throttle (unchanged). Serialize the count-then-insert under one lock.
  perform pg_advisory_xact_lock(hashtext('invite_redeem_throttle'));

  select count(*) into v_count from public.rate_limits
    where endpoint = 'invite_redeem_global' and created_at > now() - c_global_window;
  if v_count >= c_global_max then
    return jsonb_build_object('success', false, 'error', 'rate_limited');
  end if;

  select count(*) into v_count from public.rate_limits
    where endpoint = 'invite_redeem' and ip_address = v_actor::text and created_at > now() - c_per_caller_window;
  if v_count >= c_per_caller_max then
    return jsonb_build_object('success', false, 'error', 'rate_limited');
  end if;

  insert into public.rate_limits (ip_address, endpoint) values (v_actor::text, 'invite_redeem');
  insert into public.rate_limits (ip_address, endpoint) values (v_actor::text, 'invite_redeem_global');

  if random() < 0.02 then
    delete from public.rate_limits where created_at < now() - interval '2 hours';
  end if;

  v_hash := encode(extensions.digest(upper(p_code), 'sha256'), 'hex');

  select * into v_invite
  from public.invitation_codes
  where code_hash = v_hash and used_by is null and expires_at > now()
  for update skip locked;

  if not found then
    return jsonb_build_object('success', false, 'error', 'invalid_or_expired');
  end if;

  -- HO-05: a named code requires the caller's verified email to equal the recipient. There is
  -- no private-relay carve-out, so a relay address cannot take a named invite; relay sign-ups
  -- use open codes, which carry no recipient and are bearer by design.
  if v_invite.recipient_email is not null
     and lower(btrim(v_invite.recipient_email)) <> v_verified_email then
    return jsonb_build_object('success', false, 'error', 'email_mismatch');
  end if;

  -- The new member email is the named recipient for a named code, otherwise the caller's own
  -- verified email. The existing-member lookup therefore keys off the caller's identity, so an
  -- open code cannot be consumed under someone else's email.
  v_member_email := coalesce(lower(btrim(v_invite.recipient_email)), v_verified_email);

  select id into v_existing_member_id
    from public.members
   where lower(btrim(email)) = v_member_email and status in ('active', 'pending')
   order by created_at asc limit 1;

  if v_existing_member_id is not null then
    update public.invitation_codes
       set used_by = v_existing_member_id, used_at = coalesce(used_at, now())
     where id = v_invite.id and used_by is null;
    return jsonb_build_object('success', false, 'error', 'already_member');
  end if;

  insert into public.members (id, full_name, email, tier, status, city, industry)
  values (v_actor, p_full_name, v_member_email, v_invite.tier_grant, 'active', p_city, p_industry);

  v_admin_role := coalesce(v_invite.staff_role_grant, case when v_invite.grants_admin then 'admin' else null end);
  v_is_staff := v_admin_role is not null;

  if v_is_staff then
    insert into public.admin_roles (member_id, role) values (v_actor, v_admin_role)
    on conflict (member_id) do update set role = excluded.role;
  end if;

  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) ||
    jsonb_build_object('tier', v_invite.tier_grant::text, 'is_admin', v_is_staff, 'admin_role', v_admin_role)
  where id = v_actor;

  update public.invitation_codes set used_by = v_actor, used_at = now() where id = v_invite.id;

  return jsonb_build_object('success', true, 'tier', v_invite.tier_grant::text, 'is_admin', v_is_staff, 'admin_role', v_admin_role);
end;
$function$;
