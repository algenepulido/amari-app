-- Regression tests for batch 2 (HO-01, HO-02, HO-08). Gold and above may read the map
-- and approved projects; Member, Silver and non-members may not; a stale tier claim does
-- not elevate.
begin;
select plan(6);

insert into auth.users (id, aud, role, email, instance_id, created_at, updated_at) values
 ('cccc0000-0000-0000-0000-000000000001','authenticated','authenticated','t2_gold@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('cccc0000-0000-0000-0000-000000000002','authenticated','authenticated','t2_silver@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('cccc0000-0000-0000-0000-000000000003','authenticated','authenticated','t2_nomember@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('cccc0000-0000-0000-0000-000000000004','authenticated','authenticated','t2_admin@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now());
insert into public.members (id, display_id, tier, status, full_name, email) values
 ('cccc0000-0000-0000-0000-000000000001','PGT2-G','gold'::membership_tier,'active'::member_status,'T2 Gold','t2_gold@pgtap.invalid'),
 ('cccc0000-0000-0000-0000-000000000002','PGT2-S','silver'::membership_tier,'active'::member_status,'T2 Silver','t2_silver@pgtap.invalid'),
 ('cccc0000-0000-0000-0000-000000000004','PGT2-A','gold'::membership_tier,'active'::member_status,'T2 Admin','t2_admin@pgtap.invalid');
insert into public.admin_roles (member_id, role) values
 ('cccc0000-0000-0000-0000-000000000004','admin');
-- The HO-03 trigger from batch 1 correctly forces a non-admin's project to pending, so the
-- project starts pending and an admin approves it through the real path. The creator is the
-- admin, so the Gold read under test passes only through the tier gate, not a
-- creator-owns-own-project path.
insert into public.projects (id, creator_id, name, description, category, region_id, status) values
 ('cccc0000-0000-0000-0000-0000000000f1','cccc0000-0000-0000-0000-000000000004','PGT2 Proj','d','tech'::project_category,(select id from region_centroids limit 1),'pending'::project_status);
insert into public.map_cache_projects (id, project_id, name, description, category, creator_first_name, display_label, display_point, refreshed_at)
 values (gen_random_uuid(),'cccc0000-0000-0000-0000-0000000000f1','PGT2 Cache','d','tech'::project_category,'G','L',ST_SetSRID(ST_MakePoint(151.2,-33.8),4326),now());

-- An admin approves the project before the role drops to authenticated. The HO-03 trigger
-- checks is_admin() from the JWT claim, so set the admin claim first; the update runs with
-- the setup role, the same way p0_authz_regression approves a project.
select set_config('request.jwt.claims','{"sub":"cccc0000-0000-0000-0000-000000000004","role":"authenticated"}', true);
update public.projects set status='approved'::project_status where id='cccc0000-0000-0000-0000-0000000000f1';

-- Production grants authenticated a table-level SELECT on the map cache and projects; that
-- grant together with the old USING(true) policy was the HO-01/HO-02 exposure. A
-- migration-only build omits the grant, so add it here (transaction scoped, rolled back) to
-- exercise the RLS gate itself rather than the table privilege.
grant select on public.map_cache_projects to authenticated;
grant select on public.projects to authenticated;

set local role authenticated;

select set_config('request.jwt.claims','{"sub":"cccc0000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select cmp_ok((select count(*) from public.map_cache_projects), '>=', 1::bigint, 'HO-01: a Gold member can read the map cache');
select cmp_ok((select count(*) from public.projects where status='approved'), '>=', 1::bigint, 'HO-02: a Gold member can read approved projects');

select set_config('request.jwt.claims','{"sub":"cccc0000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is((select count(*)::int from public.map_cache_projects), 0, 'HO-01: a Silver member cannot read the map cache');
select is((select count(*)::int from public.projects where status='approved'), 0, 'HO-02: a Silver member cannot read approved projects');

select set_config('request.jwt.claims','{"sub":"cccc0000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select is((select count(*)::int from public.map_cache_projects), 0, 'HO-01: a non-member cannot read the map cache');

select set_config('request.jwt.claims','{"sub":"cccc0000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"tier":"gold"}}', true);
select is(public.get_member_tier()::text, 'member', 'HO-08: a stale gold tier claim does not elevate a non-member');

select * from finish();
rollback;
