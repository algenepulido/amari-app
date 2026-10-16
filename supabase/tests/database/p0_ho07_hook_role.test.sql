-- HO-07 follow-up regression. The access-token hook failed on the real login path because it
-- ran as SECURITY INVOKER: Supabase Auth executes it as supabase_auth_admin, a role RLS does not
-- let read members or admin_roles, so everyone was stamped Member. The fix makes the hook
-- SECURITY DEFINER, so it reads those rows as its owner regardless of the calling role, which is
-- what makes it correct under supabase_auth_admin. postgres cannot SET ROLE to supabase_auth_admin
-- in the local database, so rather than assume that role these assertions prove the properties
-- that make the hook caller-independent: it is SECURITY DEFINER, its stamping logic is right, and
-- execute is restricted to the auth role. get_admin_role is checked for the lookup restriction.
begin;
select plan(8);

insert into auth.users (id, aud, role, email, instance_id, created_at, updated_at) values
 ('eeee0000-0000-0000-0000-00000000c001','authenticated','authenticated','h_gold@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('eeee0000-0000-0000-0000-00000000c004','authenticated','authenticated','h_admin@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('eeee0000-0000-0000-0000-00000000c005','authenticated','authenticated','h_admin2@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('eeee0000-0000-0000-0000-00000000c006','authenticated','authenticated','h_suspadmin@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now());

insert into public.members (id, display_id, tier, status, full_name, email) values
 ('eeee0000-0000-0000-0000-00000000c001','H07-G','gold','active','H Gold','h_gold@pgtap.invalid'),
 ('eeee0000-0000-0000-0000-00000000c004','H07-A','gold','active','H Admin','h_admin@pgtap.invalid'),
 ('eeee0000-0000-0000-0000-00000000c005','H07-A2','gold','active','H Admin2','h_admin2@pgtap.invalid'),
 ('eeee0000-0000-0000-0000-00000000c006','H07-SA','gold','suspended','H SuspAdmin','h_suspadmin@pgtap.invalid');

insert into public.admin_roles (member_id, role) values
 ('eeee0000-0000-0000-0000-00000000c004','admin'),
 ('eeee0000-0000-0000-0000-00000000c005','admin'),
 ('eeee0000-0000-0000-0000-00000000c006','admin');

-- The property that fixes the login path: the hook runs as its owner, not the caller.
select is(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'custom_access_token_hook'),
  true,
  'hook is SECURITY DEFINER, so it reads members and admin_roles regardless of the caller role' );

-- The stamping logic is correct (owner execution is how SECURITY DEFINER runs it for everyone).
select is(
  (public.custom_access_token_hook(jsonb_build_object('user_id','eeee0000-0000-0000-0000-00000000c001','claims',jsonb_build_object('app_metadata','{}'::jsonb))) -> 'claims' -> 'app_metadata' ->> 'tier'),
  'gold', 'hook stamps the active member tier' );
select is(
  (public.custom_access_token_hook(jsonb_build_object('user_id','eeee0000-0000-0000-0000-00000000c004','claims',jsonb_build_object('app_metadata','{}'::jsonb))) -> 'claims' -> 'app_metadata' ->> 'is_admin'),
  'true', 'hook stamps is_admin for an active admin' );
select is(
  (public.custom_access_token_hook(jsonb_build_object('user_id','eeee0000-0000-0000-0000-00000000c006','claims',jsonb_build_object('app_metadata','{}'::jsonb))) -> 'claims' -> 'app_metadata' ->> 'is_admin'),
  'false', 'hook does not stamp is_admin for a suspended admin' );

-- Execute is locked to the auth role that invokes the hook during login.
select ok(
  has_function_privilege('supabase_auth_admin', 'public.custom_access_token_hook(jsonb)', 'EXECUTE'),
  'supabase_auth_admin can execute the hook' );
select ok(
  not has_function_privilege('authenticated', 'public.custom_access_token_hook(jsonb)', 'EXECUTE'),
  'an ordinary authenticated user cannot execute the hook' );

-- get_admin_role: a non-admin cannot read another member's admin role; an active admin can.
select set_config('request.jwt.claims','{"sub":"eeee0000-0000-0000-0000-00000000c001","role":"authenticated"}', true);
select is(
  public.get_admin_role('eeee0000-0000-0000-0000-00000000c004'::uuid),
  null::text,
  'get_admin_role: a non-admin cannot learn another member admin role' );
select set_config('request.jwt.claims','{"sub":"eeee0000-0000-0000-0000-00000000c004","role":"authenticated"}', true);
select is(
  public.get_admin_role('eeee0000-0000-0000-0000-00000000c005'::uuid),
  'admin',
  'get_admin_role: an active admin can look up another member admin role' );

select * from finish();
rollback;
