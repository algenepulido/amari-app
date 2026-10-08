-- HO-07 follow-up: a suspended admin is not an admin through get_admin_role or the
-- access-token hook, and is_admin / get_member_tier are no longer executable by anon.
begin;
select plan(7);

insert into auth.users (id, aud, role, email, instance_id, created_at, updated_at) values
 ('dddd0000-0000-0000-0000-000000000001','authenticated','authenticated','ho7_active@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('dddd0000-0000-0000-0000-000000000002','authenticated','authenticated','ho7_susp@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now());
insert into public.members (id, display_id, tier, status, full_name, email) values
 ('dddd0000-0000-0000-0000-000000000001','HO7-A','gold'::membership_tier,'active'::member_status,'HO7 Active Admin','ho7_active@pgtap.invalid'),
 ('dddd0000-0000-0000-0000-000000000002','HO7-S','gold'::membership_tier,'suspended'::member_status,'HO7 Suspended Admin','ho7_susp@pgtap.invalid');
insert into public.admin_roles (member_id, role) values
 ('dddd0000-0000-0000-0000-000000000001','admin'),
 ('dddd0000-0000-0000-0000-000000000002','admin');

-- get_admin_role honors active status
select is( public.get_admin_role('dddd0000-0000-0000-0000-000000000001'::uuid), 'admin', 'HO-07: an active admin has an admin role' );
select is( public.get_admin_role('dddd0000-0000-0000-0000-000000000002'::uuid), null, 'HO-07: a suspended admin has no admin role' );

-- access-token hook stamps is_admin from an active admin only
select is(
  (public.custom_access_token_hook(
     jsonb_build_object('user_id','dddd0000-0000-0000-0000-000000000002','claims', jsonb_build_object('app_metadata','{}'::jsonb))
   ) -> 'claims' -> 'app_metadata' ->> 'is_admin'),
  'false',
  'HO-07: a suspended admin is not stamped is_admin in the token' );
select is(
  (public.custom_access_token_hook(
     jsonb_build_object('user_id','dddd0000-0000-0000-0000-000000000001','claims', jsonb_build_object('app_metadata','{}'::jsonb))
   ) -> 'claims' -> 'app_metadata' ->> 'is_admin'),
  'true',
  'HO-07 control: an active admin is stamped is_admin' );

-- function grants: is_admin and get_member_tier are not executable by anon, but are by authenticated
select ok( not has_function_privilege('anon', 'public.is_admin()', 'EXECUTE'), 'is_admin is not executable by anon' );
select ok( not has_function_privilege('anon', 'public.get_member_tier()', 'EXECUTE'), 'get_member_tier is not executable by anon' );
select ok( has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE'), 'is_admin is executable by authenticated' );

select * from finish();
rollback;
