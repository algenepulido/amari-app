-- HO-07 follow-up from the audit. Two fixes to the access-token hook and get_admin_role.
--
-- 1. custom_access_token_hook ran as SECURITY INVOKER, so Supabase Auth executed it as
--    supabase_auth_admin, a role that RLS does not let read members or admin_roles. Under the
--    real login path every account, including Gold, Platinum, Laureate and an active admin,
--    came back as Member and not admin, while the postgres-run test hid it. Make the hook
--    SECURITY DEFINER so it reads those rows as its owner regardless of the calling role, and
--    lock execute down to supabase_auth_admin so nothing else can call it.
--
-- 2. get_admin_role accepted any member id from any authenticated caller, so anyone could learn
--    whether another member is an administrator. Restrict it to the caller's own role, with an
--    active administrator still able to look up another member. The caller's admin status is
--    checked inline, not through is_admin(), to avoid recursion.

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
    and (
      coalesce(p_member_id, auth.uid()) = auth.uid()
      or exists (
        select 1
        from public.admin_roles car
        join public.members cm on cm.id = car.member_id
        where car.member_id = auth.uid()
          and cm.status = 'active'
      )
    )
  limit 1;
$fn$;

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
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

-- Only Supabase Auth may run the hook. Revoke the broad grants and hand execute to the auth
-- role that invokes it during login.
revoke execute on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    execute 'grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin';
  end if;
end $$;
