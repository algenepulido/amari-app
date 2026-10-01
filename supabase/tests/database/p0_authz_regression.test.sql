-- Regression tests for the P0 batch 1 fixes (HO-07, HO-03, HO-25, HO-04).
-- Each prohibited action must fail and each allowed action must succeed.
begin;
select plan(7);

-- Fixtures
insert into auth.users (id, aud, role, email, instance_id, created_at, updated_at) values
 ('aaaa0000-0000-0000-0000-000000000001','authenticated','authenticated','t_admin@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('aaaa0000-0000-0000-0000-000000000002','authenticated','authenticated','t_suspadmin@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('aaaa0000-0000-0000-0000-000000000003','authenticated','authenticated','t_member@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('aaaa0000-0000-0000-0000-000000000004','authenticated','authenticated','t_nomember@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now());
insert into public.members (id, display_id, tier, status, full_name, email) values
 ('aaaa0000-0000-0000-0000-000000000001','PGT-A','gold','active','T Admin','t_admin@pgtap.invalid'),
 ('aaaa0000-0000-0000-0000-000000000002','PGT-S','gold','suspended','T SuspAdmin','t_suspadmin@pgtap.invalid'),
 ('aaaa0000-0000-0000-0000-000000000003','PGT-M','member','active','T Member','t_member@pgtap.invalid');
insert into public.admin_roles (member_id, role) values
 ('aaaa0000-0000-0000-0000-000000000001','admin'),
 ('aaaa0000-0000-0000-0000-000000000002','admin');
insert into public.projects (id, creator_id, name, description, category, region_id, status) values
 ('aaaa0000-0000-0000-0000-0000000000f1','aaaa0000-0000-0000-0000-000000000003','PGT Proj','d','tech'::project_category,(select id from region_centroids limit 1),'pending'::project_status);
insert into public.events (type, title, min_tier, starts_at, is_featured, capacity) values
 ((select enumlabel from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='event_type' order by e.enumsortorder limit 1)::event_type,'PGT Event','member'::membership_tier, now()+interval '7 days', false, 10);

-- HO-07
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select ok( public.is_admin() = false, 'HO-07: a suspended admin is not treated as admin' );
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select ok( public.is_admin() = true, 'HO-07 control: an active admin is still admin' );

-- HO-03
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select throws_ok(
  $$ update public.projects set status='approved'::project_status where id='aaaa0000-0000-0000-0000-0000000000f1' $$,
  'Only an admin can change a project status',
  'HO-03: a member cannot approve their own project' );
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select lives_ok(
  $$ update public.projects set status='approved'::project_status where id='aaaa0000-0000-0000-0000-0000000000f1' $$,
  'HO-03 control: an admin can approve a project' );

-- HO-25
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select is( (public.rsvp_to_event((select id from public.events where title='PGT Event'))->>'success'), 'true', 'HO-25: a first RSVP to a capacity event reports success' );
select is( (select count(*)::int from public.event_rsvps where event_id=(select id from public.events where title='PGT Event')), 1, 'HO-25: that RSVP wrote exactly one row' );

-- HO-04
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-000000000004","role":"authenticated"}', true);
do $$ begin for i in 1..10 loop perform public.redeem_invitation_code('BADCODE','aaaa0000-0000-0000-0000-000000000004','N','e@pgtap.invalid'); end loop; end $$;
select is( (public.redeem_invitation_code('BADCODE','aaaa0000-0000-0000-0000-000000000004','N','e@pgtap.invalid')->>'error'), 'rate_limited', 'HO-04: redeem is rate-limited after 10 attempts' );

select * from finish();
rollback;
