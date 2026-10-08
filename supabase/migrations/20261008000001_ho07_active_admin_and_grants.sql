-- HO-07 follow-up and function grants. is_admin() became active-member-aware in batch 1,
-- but the admin stamp still flowed from admin_roles with no active check through the
-- access-token hook and get_admin_role, so a suspended admin kept is_admin in their token
-- and through anything reading those. Make every admin decision require an active member,
-- and tighten the inherited PUBLIC execute on is_admin() and get_member_tier(). Applies
-- after 20261003000001.

-- get_admin_role: an admin role only counts while the member is active.
create or replace function public.get_admin_role(p_member_id uuid default auth.uid())
returns text
language sql
stable
security definer
set search_path = public
as $fn$
  select ar.role
  from public.admin_roles ar
  join public.members m on m.id = ar.member_id
  where ar.member_id = coalesce(p_member_id, auth.uid())
    and m.status = 'active'
  limit 1;
$fn$;

-- custom_access_token_hook: stamp is_admin and admin_role from an active admin only, so a
-- suspended admin loses is_admin on the next token refresh. Tier already required active.
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $fn$
declare
  claims jsonb;
  v_tier text;
  v_admin_role text;
  v_user_id uuid;
begin
  v_user_id := (event ->> 'user_id')::uuid;
  claims := event -> 'claims';

  select tier::text
  into v_tier
  from public.members
  where id = v_user_id
    and status = 'active';

  select ar.role
  into v_admin_role
  from public.admin_roles ar
  join public.members m on m.id = ar.member_id
  where ar.member_id = v_user_id
    and m.status = 'active'
  limit 1;

  claims := jsonb_set(
    claims,
    '{app_metadata}',
    coalesce(claims -> 'app_metadata', '{}'::jsonb) ||
    jsonb_build_object(
      'tier', coalesce(v_tier, 'member'),
      'is_admin', coalesce(v_admin_role is not null, false),
      'admin_role', v_admin_role
    )
  );

  event := jsonb_set(event, '{claims}', claims);
  return event;
end;
$fn$;

-- HO function grants: is_admin() and get_member_tier() carried the inherited PUBLIC execute.
-- Restrict to authenticated, matching get_admin_role.
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
revoke execute on function public.get_member_tier() from public, anon;
grant execute on function public.get_member_tier() to authenticated;
