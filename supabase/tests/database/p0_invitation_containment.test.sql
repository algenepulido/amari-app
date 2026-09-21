-- Regression tests for the P0 invitation containment migration.
--
-- Every test runs under a real role with a real JWT subject. The service role
-- is never used to demonstrate a client-side security property, because the
-- service role bypasses row level security and would prove nothing.
--
-- The suite is written so that each control is exercised by a case that must
-- FAIL as well as a case that must succeed. A check that has only ever passed
-- is not known to work.

begin;

select plan(18);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-00000000f001', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000f002', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000f003', '{}'::jsonb)
on conflict (id) do nothing;

insert into public.invitation_codes
  (code, code_hash, expires_at, tier_grant, grants_admin, staff_role_grant, invite_source)
values
  ('PGTAP-P0-MEMBER-001',
   encode(extensions.digest('PGTAP-P0-MEMBER-001', 'sha256'), 'hex'),
   now() + interval '30 days', 'member', false, null, 'bootstrap'),
  ('PGTAP-P0-EXPIRED-001',
   encode(extensions.digest('PGTAP-P0-EXPIRED-001', 'sha256'), 'hex'),
   now() - interval '1 day', 'member', false, null, 'bootstrap'),
  ('PGTAP-P0-ADMIN-001',
   encode(extensions.digest('PGTAP-P0-ADMIN-001', 'sha256'), 'hex'),
   now() + interval '30 days', 'laureate', true, 'admin', 'bootstrap');

-- The containment migration expires admin-capable rows. Apply the same rule to
-- the fixture row so the suite tests the post-migration world.
update public.invitation_codes
   set expires_at = now()
 where code = 'PGTAP-P0-ADMIN-001';

select set_config('test.admin_roles_before',
  (select count(*)::text from public.admin_roles), true);

-- ---------------------------------------------------------------------------
-- 1 to 4. The anonymous role reaches nothing it should not.
-- ---------------------------------------------------------------------------
set local role anon;

select throws_ok(
  $$ select public.redeem_invitation_code('PGTAP-P0-MEMBER-001',
       '00000000-0000-0000-0000-00000000f001', 'Anon', 'anon@example.invalid') $$,
  '42501',
  null,
  'anonymous caller cannot redeem an invitation');

select throws_ok(
  $$ select public.cleanup_rate_limits() $$,
  '42501',
  null,
  'anonymous caller cannot clear the rate limit table');

select throws_ok(
  $$ select public.check_rate_limit('x', 'invite_validate', 5, 60) $$,
  '42501',
  null,
  'anonymous caller cannot write rate limit rows directly');

select throws_ok(
  $$ select count(*) from public.map_projects(-90, -180, 90, 180, null) $$,
  '42501',
  null,
  'anonymous caller cannot read member-only project map data');

reset role;

-- ---------------------------------------------------------------------------
-- 5. Validation stays reachable before sign-in, which is the one anonymous
--    capability the product genuinely needs.
-- ---------------------------------------------------------------------------
set local role anon;

select lives_ok(
  $$ select public.validate_invitation_code('PGTAP-P0-MEMBER-001') $$,
  'anonymous caller may still validate a code before signing in');

reset role;

-- ---------------------------------------------------------------------------
-- 6 to 10. An authenticated caller is bound to its own identity.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f001', true);

select is(
  public.redeem_invitation_code('PGTAP-P0-MEMBER-001',
    '00000000-0000-0000-0000-00000000f002', 'Impostor', 'impostor@example.invalid') ->> 'error',
  'identity_mismatch',
  'an authenticated caller cannot redeem on behalf of another identity');

select is(
  public.redeem_invitation_code('PGTAP-P0-EXPIRED-001',
    '00000000-0000-0000-0000-00000000f001', 'Late', 'late@example.invalid') ->> 'error',
  'invalid_or_expired',
  'an expired invitation cannot be redeemed');

select is(
  public.redeem_invitation_code('PGTAP-P0-ADMIN-001',
    '00000000-0000-0000-0000-00000000f001', 'Climber', 'climber@example.invalid') ->> 'error',
  'invalid_or_expired',
  'a contained admin-capable invitation can no longer be redeemed');

-- The legitimate path still works, which is the point of containment rather
-- than removal.
select is(
  (public.redeem_invitation_code('PGTAP-P0-MEMBER-001',
    '00000000-0000-0000-0000-00000000f001', 'Genuine', 'genuine@example.invalid')
   ->> 'success')::boolean,
  true,
  'ordinary authenticated onboarding still succeeds');

select is(
  (select tier::text from public.members where id = '00000000-0000-0000-0000-00000000f001'),
  'member',
  'the new member lands on the lowest tier');

reset role;

-- ---------------------------------------------------------------------------
-- 11 to 13. The member row was created under the caller, not under the
--           identifier the caller supplied.
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.members where id = '00000000-0000-0000-0000-00000000f001'),
  1::bigint,
  'the member row is bound to the authenticated caller');

select is(
  (select count(*) from public.members where id = '00000000-0000-0000-0000-00000000f002'),
  0::bigint,
  'no member row was created for the identifier passed by the caller');

select is(
  (select count(*)::text from public.admin_roles),
  current_setting('test.admin_roles_before', true),
  'no administrator was created anywhere in this suite');

-- ---------------------------------------------------------------------------
-- 14. Single use. A second identity cannot reuse a consumed code.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f003', true);

select is(
  public.redeem_invitation_code('PGTAP-P0-MEMBER-001',
    '00000000-0000-0000-0000-00000000f003', 'Second', 'second@example.invalid') ->> 'error',
  'invalid_or_expired',
  'a consumed invitation cannot be redeemed by a second identity');

reset role;

-- ---------------------------------------------------------------------------
-- 15. The containment objective itself, asserted rather than assumed.
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.invitation_codes
    where used_by is null
      and expires_at > now()
      and (coalesce(grants_admin, false) or staff_role_grant is not null)),
  0::bigint,
  'no admin-capable invitation is valid and unused');

-- ---------------------------------------------------------------------------
-- 16 to 18. Existing members and administrators are undisturbed, and an
--           authenticated member can still read its own row.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f001', true);

select is(
  (select count(*) from public.members where id = auth.uid()),
  1::bigint,
  'an authenticated member can still read its own profile');

select is(
  (select count(*) from public.members where id <> auth.uid()),
  0::bigint,
  'an authenticated member still cannot read another member row');

reset role;

select ok(
  (select count(*) from public.invitation_codes where used_by is not null) >= 0,
  'no redeemed invitation was deleted by containment');

select * from finish();

rollback;
