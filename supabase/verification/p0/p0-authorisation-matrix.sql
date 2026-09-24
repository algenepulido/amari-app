\set ON_ERROR_STOP off
\pset tuples_only on
\echo '=== D. MAP AUTHORISATION MATRIX (post-migration) ==='
\echo '-- 1 anon                       expect: permission denied'
set role anon; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- 2 authenticated non-member   expect: membership required'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000009',false);
set role authenticated; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- 3 active member              expect: higher membership tier required'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
set role authenticated; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- 4 active silver              expect: higher membership tier required'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
set role authenticated; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- 5 active gold                expect: 1 row'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
set role authenticated; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- 6 active platinum            expect: 1 row'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
set role authenticated; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- 7 active laureate            expect: 1 row'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
set role authenticated; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- 8 suspended gold             expect: active membership required'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000006',false);
set role authenticated; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- 9 INACTIVE gold              expect: active membership required'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000007',false);
set role authenticated; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- 10 admin at member tier      expect: 1 row'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000008',false);
set role authenticated; select count(*) from public.map_projects(-90,-180,90,180,null); reset role;
\echo '-- gold on map_states and map_countries   expect: 1 row each'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
set role authenticated;
select count(*) from public.map_states(-90,-180,90,180,null);
select count(*) from public.map_countries(null);
reset role;

\echo ''
\echo '=== ACL AFTER MIGRATION, EXERCISED FROM REAL ROLES ==='
\echo '-- anon redeem                  expect: permission denied'
set role anon; select public.redeem_invitation_code('X','00000000-0000-0000-0000-000000000009','a','b'); reset role;
\echo '-- anon cleanup_rate_limits     expect: permission denied'
set role anon; select public.cleanup_rate_limits(); reset role;
\echo '-- authenticated cleanup        expect: permission denied'
set role authenticated; select public.cleanup_rate_limits(); reset role;
\echo '-- anon check_rate_limit        expect: permission denied'
set role anon; select public.check_rate_limit('1.1.1.1','x',5,60); reset role;
\echo '-- anon direct delete rate_limits  expect: permission denied'
set role anon; delete from public.rate_limits; reset role;
\echo '-- anon read rollback table     expect: permission denied'
set role anon; select count(*) from public.invitation_expiry_backup_20260921; reset role;
\echo '-- authenticated read rollback table  expect: permission denied'
set role authenticated; select count(*) from public.invitation_expiry_backup_20260921; reset role;
\echo '-- anon validate (must still work)  expect: {"valid": false} not an error'
set role anon; select public.validate_invitation_code('NOT-A-REAL-CODE'); reset role;

\echo ''
\echo '=== E. INVITATION REPLACEMENT TESTS ==='
select set_config('test.newcode',(select code from public.invitation_codes
  where invite_source='reissue' and recipient_email='weak.addressed@example.invalid'
    and used_by is null and expires_at > now() order by id desc limit 1),false);
\echo '-- replacement suffix length    expect: 48'
select length(code)-length(code_prefix)-1 from public.invitation_codes
 where invite_source='reissue' and recipient_email='weak.addressed@example.invalid'
   and used_by is null and expires_at > now();
\echo '-- anon validates new code      expect: true'
set role anon; select public.validate_invitation_code(current_setting('test.newcode')) ->> 'valid'; reset role;
\echo '-- anon validates expired legacy  expect: false'
set role anon; select public.validate_invitation_code('AMARI-MEMB-001') ->> 'valid'; reset role;
\echo '-- anon validates expired weak    expect: false'
set role anon; select public.validate_invitation_code('AMARI-SLVR-A3B44BDA') ->> 'valid'; reset role;
\echo '-- redeem for another identity  expect: identity_mismatch'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000009',false);
set role authenticated;
select public.redeem_invitation_code(current_setting('test.newcode'),
  '00000000-0000-0000-0000-000000000001','X','weak.addressed@example.invalid') ->> 'error';
\echo '-- intended recipient redeems   expect: success true, tier silver'
select public.redeem_invitation_code(current_setting('test.newcode'),
  '00000000-0000-0000-0000-000000000009','Weak Code Person','weak.addressed@example.invalid');
reset role;
\echo '-- admin_roles unchanged        expect: 1'
select count(*) from public.admin_roles;
\echo '-- no admin created by a replacement  expect: 0'
select count(*) from public.invitation_codes where invite_source='reissue'
  and (grants_admin or staff_role_grant is not null);
