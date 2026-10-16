-- Regression for the suspension and reactivation workflow. admin_set_member_status previously
-- wrote the status notification with the non-existent 'account_status' enum value, which rolled
-- the transaction back and left the Admin Members screen unable to suspend, reactivate or
-- deactivate anyone. These assertions drive the same three transitions the audit used and
-- confirm the status change lands and a 'system' notification is recorded.
begin;
select plan(5);

insert into auth.users (id, aud, role, email, instance_id, created_at, updated_at) values
 ('dddd0000-0000-0000-0000-00000000b001','authenticated','authenticated','sus_admin@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('dddd0000-0000-0000-0000-00000000b002','authenticated','authenticated','sus_target@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now());

insert into public.members (id, display_id, tier, status, full_name, email) values
 ('dddd0000-0000-0000-0000-00000000b001','SUS-AD','gold','active','Sus Admin','sus_admin@pgtap.invalid'),
 ('dddd0000-0000-0000-0000-00000000b002','SUS-TG','member','active','Sus Target','sus_target@pgtap.invalid');

insert into public.admin_roles (member_id, role) values
 ('dddd0000-0000-0000-0000-00000000b001','admin');

select set_config('request.jwt.claims','{"sub":"dddd0000-0000-0000-0000-00000000b001","role":"authenticated"}', true);

-- active -> suspended: the call that used to roll back now succeeds.
select is(
  (public.admin_set_member_status('dddd0000-0000-0000-0000-00000000b002','suspended'::member_status,'audit')->>'success'),
  'true',
  'suspension: active to suspended succeeds' );
select is(
  (select status::text from public.members where id = 'dddd0000-0000-0000-0000-00000000b002'),
  'suspended',
  'suspension: the member status is actually suspended' );
select is(
  (select count(*)::int from public.notifications
     where member_id = 'dddd0000-0000-0000-0000-00000000b002'
       and type = 'system' and data->>'kind' = 'account_status'),
  1,
  'suspension: a system notification recorded the status change, not a rolled-back transaction' );

-- suspended -> active, and active -> inactive, both complete.
select is(
  (public.admin_set_member_status('dddd0000-0000-0000-0000-00000000b002','active'::member_status,null)->>'success'),
  'true',
  'suspension: suspended to active succeeds' );
select is(
  (public.admin_set_member_status('dddd0000-0000-0000-0000-00000000b002','inactive'::member_status,null)->>'success'),
  'true',
  'suspension: active to inactive succeeds' );

select * from finish();
rollback;
