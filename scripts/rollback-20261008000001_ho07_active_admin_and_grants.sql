-- Rollback for 20261008000001. Restores get_admin_role and custom_access_token_hook to the
-- admin_roles-only form from 20260323000001, and restores the PUBLIC execute on is_admin()
-- and get_member_tier(). Run only to undo that migration.

create or replace function public.get_admin_role(p_member_id uuid default auth.uid())
returns text
language sql
stable
security definer
set search_path = public
as $fn$
  select role
  from public.admin_roles
  where member_id = coalesce(p_member_id, auth.uid())
  limit 1;
$fn$;

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

  select role
  into v_admin_role
  from public.admin_roles
  where member_id = v_user_id
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

grant execute on function public.is_admin() to public;
grant execute on function public.get_member_tier() to public;
