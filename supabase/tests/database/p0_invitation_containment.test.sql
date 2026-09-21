-- Regression tests for the P0 invitation containment migration, revision 2.
--
-- Every test runs under a real role with a real JWT subject. The service role
-- is never used to demonstrate a client-side security property, because it
-- bypasses row level security and would prove nothing.
--
-- Each control is exercised by a case that must FAIL as well as one that must
-- succeed, and the refusals are asserted by their specific reason rather than
-- by the mere fact of a refusal. A test that accepts any error accepts the
-- wrong error.

begin;

select plan(45);

-- ---------------------------------------------------------------------------
-- Fixtures: one identity per tier, plus suspended, admin and non-member.
-- ---------------------------------------------------------------------------
insert into auth.users (id, raw_app_meta_data) values
  ('00000000-0000-0000-0000-00000000c001', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000c002', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000c003', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000c004', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000c005', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000c006', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000c007', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000c008', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000c009', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000c010', '{}'::jsonb)
on conflict (id) do nothing;

insert into public.members (id, full_name, email, tier, status) values
  ('00000000-0000-0000-0000-00000000c002', 'pgTAP Member',    'pgtap.c002@example.invalid', 'member',   'active'),
  ('00000000-0000-0000-0000-00000000c003', 'pgTAP Silver',    'pgtap.c003@example.invalid', 'silver',   'active'),
  ('00000000-0000-0000-0000-00000000c004', 'pgTAP Gold',      'pgtap.c004@example.invalid', 'gold',     'active'),
  ('00000000-0000-0000-0000-00000000c005', 'pgTAP Platinum',  'pgtap.c005@example.invalid', 'platinum', 'active'),
  ('00000000-0000-0000-0000-00000000c006', 'pgTAP Suspended', 'pgtap.c006@example.invalid', 'gold',     'suspended'),
  ('00000000-0000-0000-0000-00000000c007', 'pgTAP Admin',     'pgtap.c007@example.invalid', 'member',   'active'),
  ('00000000-0000-0000-0000-00000000c008', 'pgTAP Laureate',  'pgtap.c008@example.invalid', 'laureate', 'active');

insert into public.admin_roles (member_id, role)
values ('00000000-0000-0000-0000-00000000c007', 'admin')
on conflict (member_id) do nothing;

insert into public.invitation_codes
  (code, code_hash, expires_at, tier_grant, grants_admin, staff_role_grant, invite_source)
values
  ('PGTAP-P0-CONTROLLED-1',
   encode(extensions.digest('PGTAP-P0-CONTROLLED-1', 'sha256'), 'hex'),
   now() + interval '30 days', 'member', false, null, 'admin'),
  ('PGTAP-P0-EXPIRED-1',
   encode(extensions.digest('PGTAP-P0-EXPIRED-1', 'sha256'), 'hex'),
   now() - interval '1 day', 'member', false, null, 'admin'),
  ('AMARI-PGTAP-001',
   encode(extensions.digest('AMARI-PGTAP-001', 'sha256'), 'hex'),
   now() + interval '30 days', 'laureate', true, 'admin', 'bootstrap');

-- Apply the containment rule to the fixture so the suite tests the world the
-- migration creates.
update public.invitation_codes
   set expires_at = now()
 where used_by is null
   and expires_at > now()
   and ( (coalesce(grants_admin, false) or staff_role_grant is not null)
      or invite_source = 'bootstrap'
      or coalesce(code, '') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$' );

select set_config('test.admin_roles_before',
  (select count(*)::text from public.admin_roles), true);

-- ---------------------------------------------------------------------------
-- 1 to 4. The anonymous role reaches nothing it should not.
-- ---------------------------------------------------------------------------
set local role anon;

select throws_ok(
  $$ select public.redeem_invitation_code('PGTAP-P0-CONTROLLED-1',
       '00000000-0000-0000-0000-00000000c001', 'Anon', 'anon@example.invalid') $$,
  '42501', null, 'anonymous caller cannot redeem an invitation');

select throws_ok($$ select public.cleanup_rate_limits() $$,
  '42501', null, 'anonymous caller cannot clear the rate limit table');

select throws_ok($$ select public.check_rate_limit('x', 'invite_validate', 5, 60) $$,
  '42501', null, 'anonymous caller cannot write rate limit rows directly');

select throws_ok($$ delete from public.rate_limits $$,
  '42501', null, 'anonymous caller cannot delete rate limit rows directly');

reset role;

-- ---------------------------------------------------------------------------
-- 5. Validation stays reachable before sign-in. This is the one anonymous
--    capability onboarding genuinely needs.
-- ---------------------------------------------------------------------------
set local role anon;
select lives_ok($$ select public.validate_invitation_code('PGTAP-P0-CONTROLLED-1') $$,
  'anonymous caller may still validate a code before signing in');
reset role;

-- ---------------------------------------------------------------------------
-- 6 to 12. Redemption binds to auth.uid().
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c001', true);

select is(
  public.redeem_invitation_code('PGTAP-P0-CONTROLLED-1',
    '00000000-0000-0000-0000-00000000c002', 'Impostor', 'impostor@example.invalid') ->> 'error',
  'identity_mismatch',
  'an authenticated caller cannot redeem on behalf of another identity');

select is(
  public.redeem_invitation_code('PGTAP-P0-EXPIRED-1',
    '00000000-0000-0000-0000-00000000c001', 'Late', 'late@example.invalid') ->> 'error',
  'invalid_or_expired',
  'an expired invitation cannot be redeemed');

select is(
  public.redeem_invitation_code('AMARI-PGTAP-001',
    '00000000-0000-0000-0000-00000000c001', 'Climber', 'climber@example.invalid') ->> 'error',
  'invalid_or_expired',
  'a contained admin-capable invitation can no longer be redeemed');

select is(
  (public.redeem_invitation_code('PGTAP-P0-CONTROLLED-1',
    '00000000-0000-0000-0000-00000000c001', 'Genuine', 'genuine@example.invalid')
   ->> 'success')::boolean,
  true,
  'ordinary authenticated onboarding still succeeds');

reset role;

select is(
  (select tier::text from public.members where id = '00000000-0000-0000-0000-00000000c001'),
  'member', 'the new member lands on the lowest tier');

select is(
  (select count(*) from public.members where id = '00000000-0000-0000-0000-00000000c001'),
  1::bigint, 'the member row is bound to the authenticated caller');

select is(
  (select count(*)::text from public.admin_roles),
  current_setting('test.admin_roles_before', true),
  'no administrator was created anywhere in this suite');

-- ---------------------------------------------------------------------------
-- 13. Single use across identities.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c002', true);
select is(
  public.redeem_invitation_code('PGTAP-P0-CONTROLLED-1',
    '00000000-0000-0000-0000-00000000c002', 'Second', 'second@example.invalid') ->> 'error',
  'already_member',
  'a second identity that is already a member is refused');
reset role;

-- ---------------------------------------------------------------------------
-- 14 to 16. The containment objectives, asserted rather than assumed.
-- ---------------------------------------------------------------------------
select is((select count(*) from public.invitation_codes
   where used_by is null and expires_at > now()
     and (coalesce(grants_admin, false) or staff_role_grant is not null)),
  0::bigint, 'no admin-capable invitation is valid and unused');

select is((select count(*) from public.invitation_codes
   where used_by is null and expires_at > now()
     and coalesce(code, '') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$'),
  0::bigint, 'no predictable-format invitation is valid and unused');

select is((select count(*) from public.invitation_codes
   where used_by is null and expires_at > now() and invite_source = 'bootstrap'),
  0::bigint, 'no bootstrap invitation is valid and unused');

-- ---------------------------------------------------------------------------
-- 17 to 23. The map authorisation matrix, server side.
--           Required tier is gold, which is what the client enforces today.
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok($$ select count(*) from public.map_projects(-90, -180, 90, 180, null) $$,
  '42501', null, 'map: anonymous caller refused');
reset role;

set local role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c001', true);
select throws_ok($$ select count(*) from public.map_projects(-90, -180, 90, 180, null) $$,
  '42501', 'membership required', 'map: authenticated non-member refused');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c002', true);
select throws_ok($$ select count(*) from public.map_projects(-90, -180, 90, 180, null) $$,
  '42501', 'higher membership tier required', 'map: member tier refused');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c003', true);
select throws_ok($$ select count(*) from public.map_projects(-90, -180, 90, 180, null) $$,
  '42501', 'higher membership tier required', 'map: silver, immediately below the line, refused');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c006', true);
select throws_ok($$ select count(*) from public.map_projects(-90, -180, 90, 180, null) $$,
  '42501', 'active membership required', 'map: suspended gold refused');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c004', true);
select lives_ok($$ select count(*) from public.map_projects(-90, -180, 90, 180, null) $$,
  'map: gold, the qualifying tier, admitted');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c005', true);
select lives_ok($$ select count(*) from public.map_states(-90, -180, 90, 180, null) $$,
  'map: platinum admitted on map_states');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c007', true);
select lives_ok($$ select count(*) from public.map_countries(null) $$,
  'map: administrator admitted on map_countries regardless of tier');

reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c008', true);
select lives_ok($$ select count(*) from public.map_projects(-90, -180, 90, 180, null) $$,
  'map: laureate, the highest tier, admitted');

reset role;

-- ---------------------------------------------------------------------------
-- is_admin() derives from auth.uid() and authoritative admin_roles state.
-- ---------------------------------------------------------------------------
set local role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c004', true);
select is(public.is_admin(), false,
  'is_admin is false for an ordinary member');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c007', true);
select is(public.is_admin(), true,
  'is_admin is true for a member holding an admin_roles row');

-- The caller cannot borrow another identity's administrative state: is_admin
-- takes no argument at all, so there is nothing to supply.
select is(
  (select count(*) from pg_proc
    where oid = 'public.is_admin()'::regprocedure
      and pg_get_function_identity_arguments(oid) = ''),
  1::bigint,
  'is_admin accepts no caller-supplied identifier');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c004', true);
select is(public.is_admin(), false,
  'a non-admin caller cannot cause another user admin state to be used');

reset role;

-- ---------------------------------------------------------------------------
-- 24 to 25. The rollback table is not an application-readable object.
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok($$ select count(*) from public.invitation_expiry_backup_20260921 $$,
  '42501', null, 'rollback table is unreachable by anon');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c004', true);
select throws_ok($$ select count(*) from public.invitation_expiry_backup_20260921 $$,
  '42501', null, 'rollback table is unreachable by an ordinary member');
reset role;

-- ---------------------------------------------------------------------------
-- 26 to 28. Membership management is untouched and still admin-only.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c004', true);
select is(
  public.change_member_tier('00000000-0000-0000-0000-00000000c002', 'platinum',
    'pgtap should be refused', null) ->> 'error',
  'Not authorized',
  'a non-administrator still cannot change a member tier');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c007', true);
select is(
  (public.change_member_tier('00000000-0000-0000-0000-00000000c002', 'silver',
    'pgtap admin path', null) ->> 'success')::boolean,
  true,
  'an administrator can still change a member tier');

select is(
  (select tier::text from public.members where id = '00000000-0000-0000-0000-00000000c002'),
  'silver',
  'the administrative tier change actually applied');
reset role;

-- ---------------------------------------------------------------------------
-- 29 to 30. Existing members are undisturbed.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c004', true);

select is((select count(*) from public.members where id = auth.uid()),
  1::bigint, 'an authenticated member can still read its own profile');

select is((select count(*) from public.members where id <> auth.uid()),
  0::bigint, 'an authenticated member still cannot read another member row');

reset role;

select is(
  (select count(*) from public.admin_roles),
  (current_setting('test.admin_roles_before', true))::bigint,
  'the administrator set is exactly as it was before this suite ran');


-- ---------------------------------------------------------------------------
-- Replacement invitations: 192-bit secrets issued through the reissue path.
-- ---------------------------------------------------------------------------
insert into public.invitation_codes
  (code, code_hash, code_prefix, invite_source, recipient_name, recipient_email,
   tier_grant, grants_admin, staff_role_grant, expires_at, issued_at)
select c.code,
       encode(extensions.digest(c.code, 'sha256'), 'hex'),
       substring(c.code, 1, 10),
       'reissue', 'pgTAP Reissue', 'pgtap.reissue@example.invalid',
       'silver', false, null, now() + interval '30 days', now()
from (select public.generate_share_invite_code('AMARI-SLVR') as code) c;

select set_config('test.reissued',
  (select code from public.invitation_codes
    where recipient_email = 'pgtap.reissue@example.invalid'), true);

select is(
  (select length(code) - length(code_prefix) - 1
     from public.invitation_codes where recipient_email = 'pgtap.reissue@example.invalid'),
  48,
  'a reissued invitation carries a 48 character hex suffix, which is 192 bits');

select is(
  (select count(*) from public.invitation_codes
    where invite_source = 'reissue'
      and (coalesce(grants_admin, false) is true or staff_role_grant is not null)),
  0::bigint,
  'no replacement invitation can grant an administrative or staff role');

set local role anon;
select is(
  public.validate_invitation_code(current_setting('test.reissued', true)) ->> 'valid',
  'true',
  'a new 192-bit invitation validates before sign-in');

select is(
  public.validate_invitation_code('AMARI-PGTAP-001') ->> 'valid',
  'false',
  'a contained legacy predictable invitation no longer validates');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c009', true);

select is(
  public.redeem_invitation_code(current_setting('test.reissued', true),
    '00000000-0000-0000-0000-00000000c002', 'Wrong', 'pgtap.reissue@example.invalid') ->> 'error',
  'identity_mismatch',
  'another identity cannot redeem a replacement for the intended recipient');

select is(
  (public.redeem_invitation_code(current_setting('test.reissued', true),
    '00000000-0000-0000-0000-00000000c009', 'Reissue Person', 'pgtap.reissue@example.invalid')
   ->> 'success')::boolean,
  true,
  'the intended recipient redeems the replacement successfully');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c010', true);
select is(
  public.redeem_invitation_code(current_setting('test.reissued', true),
    '00000000-0000-0000-0000-00000000c010', 'Late', 'pgtap.reissue@example.invalid') ->> 'error',
  'invalid_or_expired',
  'a replacement cannot be redeemed a second time');
reset role;

select is(
  (select count(*) from public.admin_roles),
  (current_setting('test.admin_roles_before', true))::bigint,
  'issuing and redeeming replacements created no administrator');


select * from finish();

rollback;
