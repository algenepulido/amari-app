-- ============================================================================
-- Issue temporary invitations to external testers.
--
-- Operator fills secure-output/external-testers.csv first, with a header row:
--
--   tester_name,tester_email,platform,intended_tier
--   Ariful,ariful@example.com,both,member
--
-- platform is ios, android or both. intended_tier is normally member.
--
-- Run:
--   psql -w -v ON_ERROR_STOP=1 -v access_days=14 \
--        -f scripts/external-tester-issue.sql > secure-output/tester-codes.txt
--
-- The codes are printed once, to wherever you redirect output. Redirect into
-- secure-output, which is gitignored. Do not paste the output into chat.
--
-- Safe to re-run: it refuses to issue a second live invitation to the same
-- email while an unrevoked, unexpired one already exists.
-- ============================================================================

\set ON_ERROR_STOP on
\if :{?access_days} \else \set access_days 14 \endif

begin;

-- Acting as service_role so the invitation insert is not blocked by the
-- privileged-field guards. Transaction scoped.
select set_config('request.jwt.claim.role', 'service_role', true);

create temp table tester_input (
  tester_name   text,
  tester_email  text,
  platform      text,
  intended_tier text
) on commit drop;

\copy tester_input from 'secure-output/external-testers.csv' with (format csv, header true)

-- Normalise and validate before writing anything.
update tester_input
   set tester_email = lower(btrim(tester_email)),
       tester_name  = btrim(tester_name),
       platform     = lower(btrim(platform)),
       intended_tier = lower(btrim(coalesce(nullif(intended_tier, ''), 'member')));

do $validate$
declare
  v_bad integer;
  v_dupe integer;
begin
  select count(*) into v_bad from tester_input
   where tester_name is null or tester_name = ''
      or tester_email is null or tester_email not like '%@%'
      or platform not in ('ios', 'android', 'both')
      or intended_tier not in ('member', 'silver', 'gold', 'platinum', 'laureate');
  if v_bad > 0 then
    raise exception '% row(s) in external-testers.csv are invalid. Check name, email, platform (ios/android/both) and tier.', v_bad;
  end if;

  select count(*) into v_bad from tester_input where intended_tier in ('platinum', 'laureate');
  if v_bad > 0 then
    raise exception '% row(s) request platinum or laureate. External testers should not hold the top tiers. Override deliberately if you really mean it.', v_bad;
  end if;

  select count(*) into v_dupe from (
    select tester_email from tester_input group by tester_email having count(*) > 1
  ) d;
  if v_dupe > 0 then
    raise exception '% duplicate email(s) in external-testers.csv', v_dupe;
  end if;

  select count(*) into v_bad
    from tester_input t
    join public.external_tester_access e on lower(e.tester_email) = t.tester_email
   where e.revoked_at is null and e.access_expires_at > now();
  if v_bad > 0 then
    raise exception '% tester(s) already hold live access. Revoke first or remove them from the CSV.', v_bad;
  end if;
end;
$validate$;

-- Issue one 192-bit invitation per tester, addressed to them, never admin.
with issued as (
  insert into public.invitation_codes (
    code, code_hash, code_prefix, invite_source,
    recipient_name, recipient_email, tier_grant,
    grants_admin, staff_role_grant, expires_at, issued_at
  )
  select
    gen.code,
    encode(extensions.digest(gen.code, 'sha256'), 'hex'),
    substring(gen.code, 1, 10),
    'admin',
    t.tester_name,
    t.tester_email,
    t.intended_tier::membership_tier,
    false,
    null,
    now() + (:'access_days' || ' days')::interval,
    now()
  from tester_input t
  cross join lateral (
    select public.generate_share_invite_code(
      case t.intended_tier
        when 'gold'   then 'AMARI-GOLD'
        when 'silver' then 'AMARI-SLVR'
        else 'AMARI-MEMB'
      end
    ) as code
  ) gen
  returning id, code, recipient_name, recipient_email, tier_grant, expires_at
)
insert into public.external_tester_access (
  tester_name, tester_email, platform, intended_tier,
  invitation_id, access_expires_at, notes
)
select i.recipient_name, i.recipient_email, t.platform, i.tier_grant,
       i.id, i.expires_at, 'hiring trial, issued by external-tester-issue.sql'
from issued i
join tester_input t on t.tester_email = i.recipient_email;

-- Print the codes once. This is the only place they appear.
\echo ''
\echo '=== EXTERNAL TESTER INVITATIONS. Distribute individually. Do not paste into chat. ==='
select
  e.tester_name       as name,
  e.tester_email      as email,
  e.platform          as platform,
  e.intended_tier     as tier,
  c.code              as invitation_code,
  to_char(e.access_expires_at, 'YYYY-MM-DD') as expires
from public.external_tester_access e
join public.invitation_codes c on c.id = e.invitation_id
where e.revoked_at is null
  and e.granted_at > now() - interval '1 minute'
order by e.tester_name;

\echo ''
\echo '=== Summary ==='
select count(*) || ' tester invitation(s) issued, expiring in ' || :'access_days' || ' days'
from public.external_tester_access
where granted_at > now() - interval '1 minute';

commit;
