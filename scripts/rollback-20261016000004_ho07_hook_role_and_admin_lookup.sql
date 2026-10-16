-- Rollback for 20261016000004. Restores get_admin_role and custom_access_token_hook to the
-- 20261008000001 version: get_admin_role without the caller restriction, and the hook as
-- SECURITY INVOKER with the default public execute. Note this restores the broken login
-- behavior (the hook cannot read members or admin_roles under supabase_auth_admin) and the
-- information-disclosure on get_admin_role. Run only to undo the fix.

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

grant execute on function public.custom_access_token_hook(jsonb) to public;
