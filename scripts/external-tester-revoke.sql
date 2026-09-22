-- ============================================================================
-- Revoke external tester access.
--
-- Run:
--   All testers, the normal end-of-trial case:
--     psql -w -v ON_ERROR_STOP=1 -v who=all -f scripts/external-tester-revoke.sql
--
--   One tester:
--     psql -w -v ON_ERROR_STOP=1 -v who=ariful@example.com -f scripts/external-tester-revoke.sql
--
--   See what would happen without changing anything:
--     psql -w -v ON_ERROR_STOP=1 -v who=all -v dry_run=on -f scripts/external-tester-revoke.sql
--
-- dry_run defaults to ON. You must pass -v dry_run=off to make changes.
--
-- What it does, in one transaction:
--   expires any unredeemed tester invitation, so it can no longer be used;
--   suspends the member account of any tester who did redeem;
--   stamps revoked_at on the tracking row.
--
-- Suspension is the real control. Every member-reachable RPC gates on
-- is_active_member(), so a suspended tester is refused by the database, not
-- merely hidden by the app.
--
-- It does NOT delete anything. Members, invitations and history are preserved.
-- ============================================================================

\set ON_ERROR_STOP on
\if :{?who} \else \set who all \endif
\if :{?dry_run} \else \set dry_run on \endif

begin;

select set_config('request.jwt.claim.role', 'service_role', true);

create temp table revoke_target on commit drop as
select e.id, e.tester_name, e.tester_email, e.invitation_id, e.member_id,
       c.used_by is not null as invitation_redeemed,
       m.status::text        as current_member_status
  from public.external_tester_access e
  left join public.invitation_codes c on c.id = e.invitation_id
  left join public.members m on m.id = coalesce(e.member_id, c.used_by)
 where e.revoked_at is null
   and (:'who' = 'all' or lower(e.tester_email) = lower(:'who'));

\echo ''
\echo '=== Testers in scope ==='
select tester_name, tester_email,
       case when invitation_redeemed then 'redeemed, has an account' else 'never redeemed' end as state,
       coalesce(current_member_status, 'no member row') as member_status
from revoke_target order by tester_name;

do $check$
declare v_n integer;
begin
  select count(*) into v_n from revoke_target;
  if v_n = 0 then
    raise exception 'No matching tester with live access. Nothing to do.';
  end if;
  raise notice '% tester(s) in scope', v_n;
end;
$check$;

\if :dry_run
  \echo ''
  \echo '*** DRY RUN. Nothing was changed. Re-run with -v dry_run=off to apply. ***'
  rollback;
\else

  -- Expire any invitation that was never used.
  update public.invitation_codes c
     set expires_at = now()
    from revoke_target r
   where c.id = r.invitation_id
     and c.used_by is null
     and c.expires_at > now();

  -- Suspend the account of anyone who did redeem. This is what actually ends
  -- their access, because the member RPCs check is_active_member().
  update public.members m
     set status = 'suspended'
    from revoke_target r
   where m.id = coalesce(r.member_id, (select used_by from public.invitation_codes where id = r.invitation_id))
     and m.status <> 'suspended';

  -- Backfill member_id so the record is complete, then stamp the revocation.
  update public.external_tester_access e
     set member_id = coalesce(e.member_id, c.used_by),
         revoked_at = now(),
         revoked_reason = 'end of hiring trial'
    from revoke_target r
    left join public.invitation_codes c on c.id = r.invitation_id
   where e.id = r.id;

  \echo ''
  \echo '=== Result ==='
  select
    (select count(*) from public.external_tester_access where revoked_at is not null) || ' tester record(s) now revoked' as revoked_records
  union all
  select
    (select count(*) from public.members m
      join public.external_tester_access e on e.member_id = m.id
     where m.status = 'suspended') || ' tester account(s) suspended'
  union all
  select
    (select count(*) from public.invitation_codes c
      join public.external_tester_access e on e.invitation_id = c.id
     where c.used_by is null and c.expires_at <= now()) || ' unused tester invitation(s) expired';

  -- Fail closed: every tester this run targeted must now be revoked, and any
  -- of them who had an account must now be suspended. Scoped to revoke_target
  -- so it is correct whether this was a single tester or all of them.
  --
  -- Note for future edits: psql does not substitute :variables inside a
  -- dollar-quoted block, so do not reference them here.
  do $verify$
  declare
    v_unrevoked integer;
    v_still_active integer;
  begin
    select count(*) into v_unrevoked
      from public.external_tester_access e
      join revoke_target r on r.id = e.id
     where e.revoked_at is null;
    if v_unrevoked > 0 then
      raise exception '% targeted tester(s) were not revoked', v_unrevoked;
    end if;

    select count(*) into v_still_active
      from public.external_tester_access e
      join revoke_target r on r.id = e.id
      join public.members m on m.id = e.member_id
     where m.status <> 'suspended';
    if v_still_active > 0 then
      raise exception '% revoked tester(s) still hold an active account', v_still_active;
    end if;

    raise notice 'revoke complete and verified';
  end;
  $verify$;

  commit;
\endif
