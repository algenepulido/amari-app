-- Access-control tests for the Media V1 data layer (20261016000001).
-- Two-layer tier access: the catalog is visible to every active member, but a
-- playback authorization (the storage path) is returned only to members at or
-- above the item's min_tier. Admins bypass the tier and the published gates.
--
-- The RPCs are SECURITY DEFINER, so they are exercised as the test's default role
-- and read the caller from the jwt claims GUC. The two direct-table reads below
-- test RLS, so they run under `set local role authenticated`, because RLS does not
-- apply to a superuser.
begin;
select plan(11);

-- Fixtures
insert into auth.users (id, aud, role, email, instance_id, created_at, updated_at) values
 ('aaaa0000-0000-0000-0000-0000000000a1','authenticated','authenticated','med_admin@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('aaaa0000-0000-0000-0000-0000000000a2','authenticated','authenticated','med_gold@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('aaaa0000-0000-0000-0000-0000000000a3','authenticated','authenticated','med_silver@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('aaaa0000-0000-0000-0000-0000000000a4','authenticated','authenticated','med_member@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('aaaa0000-0000-0000-0000-0000000000a5','authenticated','authenticated','med_none@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now());

insert into public.members (id, display_id, tier, status, full_name, email) values
 ('aaaa0000-0000-0000-0000-0000000000a1','MED-AD','gold','active','Med Admin','med_admin@pgtap.invalid'),
 ('aaaa0000-0000-0000-0000-0000000000a2','MED-G','gold','active','Med Gold','med_gold@pgtap.invalid'),
 ('aaaa0000-0000-0000-0000-0000000000a3','MED-S','silver','active','Med Silver','med_silver@pgtap.invalid'),
 ('aaaa0000-0000-0000-0000-0000000000a4','MED-M','member','active','Med Member','med_member@pgtap.invalid');

insert into public.admin_roles (member_id, role) values
 ('aaaa0000-0000-0000-0000-0000000000a1','admin');

insert into public.media_items (id, media_type, title, storage_path, min_tier, published, created_by) values
 ('bbbb0000-0000-0000-0000-0000000000f1','video','Published Clip','media/clip1.mp4','gold',true,'aaaa0000-0000-0000-0000-0000000000a1'),
 ('bbbb0000-0000-0000-0000-0000000000f2','video','Draft Clip','media/clip2.mp4','gold',false,'aaaa0000-0000-0000-0000-0000000000a1');

-- Gold member: sees the catalog and can play a Gold item.
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
select is( (select count(*)::int from public.get_media_catalog()), 1, 'Gold member sees the published catalog' );
select is( (public.request_media_playback('bbbb0000-0000-0000-0000-0000000000f1')->>'allowed'), 'true', 'Gold member is allowed to play a Gold item' );

-- Silver member: the catalog is still visible (two-layer), but playback is gated.
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-0000000000a3","role":"authenticated"}', true);
select is( (select count(*)::int from public.get_media_catalog()), 1, 'Silver member still sees the catalog (two-layer)' );
select is( (public.request_media_playback('bbbb0000-0000-0000-0000-0000000000f1')->>'error'), 'tier_too_low', 'Silver member cannot play a Gold item' );

-- Basic member: playback gated, and an unpublished item does not leak.
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
select is( (public.request_media_playback('bbbb0000-0000-0000-0000-0000000000f1')->>'error'), 'tier_too_low', 'Member cannot play a Gold item' );
select is( (public.request_media_playback('bbbb0000-0000-0000-0000-0000000000f2')->>'error'), 'not_found', 'Member cannot tell an unpublished item exists' );

-- Non-member (authenticated, no members row): no catalog, no playback.
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-0000000000a5","role":"authenticated"}', true);
select is( (public.request_media_playback('bbbb0000-0000-0000-0000-0000000000f1')->>'error'), 'not_member', 'A non-member cannot get a playback authorization' );
select is( (select count(*)::int from public.get_media_catalog()), 0, 'A non-member sees an empty catalog' );

-- Admin: bypasses the gates and can play an unpublished item.
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is( (public.request_media_playback('bbbb0000-0000-0000-0000-0000000000f2')->>'allowed'), 'true', 'Admin can play an unpublished item' );

-- RLS on direct table reads (run as the authenticated role so RLS applies).
select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
set local role authenticated;
select is( (select count(*)::int from public.media_items), 0, 'A member reads no rows directly (RLS is admin-only)' );
reset role;

select set_config('request.jwt.claims','{"sub":"aaaa0000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;
select is( (select count(*)::int from public.media_items), 2, 'An admin reads both rows directly' );
reset role;

select * from finish();
rollback;
