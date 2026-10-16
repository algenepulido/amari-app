-- HO-05 regression: invitation ownership is proven by the caller's verified email on
-- auth.users, not by the p_email the app passes. Covers the three cases the audit confirmed:
-- a named code redeemed by supplying the recipient's email, an Apple private-relay bypass, and
-- an open code consumed under an existing member's email. redeem_invitation_code is SECURITY
-- DEFINER and reads the caller from the jwt claims GUC, so the calls below set that GUC.
begin;
select plan(5);

-- Callers have an auth.users row but no members row, so they are eligible to redeem. One
-- existing member sits on the email a caller will try to abuse.
insert into auth.users (id, aud, role, email, instance_id, created_at, updated_at) values
 ('cccc0000-0000-0000-0000-00000000a001','authenticated','authenticated','alice@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('cccc0000-0000-0000-0000-00000000a002','authenticated','authenticated','mallory@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('cccc0000-0000-0000-0000-00000000a003','authenticated','authenticated','privrelay777@privaterelay.appleid.com','00000000-0000-0000-0000-000000000000',now(),now()),
 ('cccc0000-0000-0000-0000-00000000a004','authenticated','authenticated','bob@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now()),
 ('cccc0000-0000-0000-0000-00000000a005','authenticated','authenticated','existing@pgtap.invalid','00000000-0000-0000-0000-000000000000',now(),now());

insert into public.members (id, display_id, tier, status, full_name, email) values
 ('cccc0000-0000-0000-0000-00000000a005','HO5-EX','member','active','Existing Member','existing@pgtap.invalid');

insert into public.invitation_codes (code, code_hash, recipient_email, tier_grant, expires_at) values
 ('HO5NAMED', encode(extensions.digest(upper('HO5NAMED'),'sha256'),'hex'), 'alice@pgtap.invalid', 'gold', now() + interval '1 day'),
 ('HO5OPEN',  encode(extensions.digest(upper('HO5OPEN'),'sha256'),'hex'),  null,                  'gold', now() + interval '1 day');

-- Case 1: a different account supplies the recipient email as p_email. It must not redeem.
select set_config('request.jwt.claims','{"sub":"cccc0000-0000-0000-0000-00000000a002","role":"authenticated"}', true);
select is(
  (public.redeem_invitation_code('HO5NAMED','cccc0000-0000-0000-0000-00000000a002','M','alice@pgtap.invalid')->>'error'),
  'email_mismatch',
  'HO-05: a named code is not redeemable by supplying the recipient email as p_email' );

-- Case 2: an Apple private-relay address does not bypass the named recipient check.
select set_config('request.jwt.claims','{"sub":"cccc0000-0000-0000-0000-00000000a003","role":"authenticated"}', true);
select is(
  (public.redeem_invitation_code('HO5NAMED','cccc0000-0000-0000-0000-00000000a003','R','alice@pgtap.invalid')->>'error'),
  'email_mismatch',
  'HO-05: an Apple private-relay address cannot take a named invite' );

-- Control: the genuine recipient, whose verified email matches, redeems it regardless of p_email.
select set_config('request.jwt.claims','{"sub":"cccc0000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
select is(
  (public.redeem_invitation_code('HO5NAMED','cccc0000-0000-0000-0000-00000000a001','A','whatever@pgtap.invalid')->>'success'),
  'true',
  'HO-05: the genuine recipient redeems the named code regardless of p_email' );

-- Case 3: an open code cannot be consumed under an existing member email; it creates the
-- caller's own membership from the verified identity.
select set_config('request.jwt.claims','{"sub":"cccc0000-0000-0000-0000-00000000a004","role":"authenticated"}', true);
select is(
  (public.redeem_invitation_code('HO5OPEN','cccc0000-0000-0000-0000-00000000a004','B','existing@pgtap.invalid')->>'success'),
  'true',
  'HO-05: an open code redeemed with another member email still creates the caller membership' );
select is(
  (select lower(btrim(email)) from public.members where id = 'cccc0000-0000-0000-0000-00000000a004'),
  'bob@pgtap.invalid',
  'HO-05: the new membership carries the caller verified email, not the p_email value' );

select * from finish();
rollback;
