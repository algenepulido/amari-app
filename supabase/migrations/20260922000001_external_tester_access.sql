-- ============================================================================
-- External tester access tracking
--
-- PROPOSED. NOT APPLIED. Requires approval before execution.
--
-- Purpose: make it possible to grant, track and revoke temporary access for
-- external testers on the live iOS app and the Android closed test, without
-- inventing anything new in the invitation system and without touching any
-- existing object.
--
-- This adds ONE table and nothing else. It alters no existing table, no
-- existing function, no existing grant and no existing policy. It is additive
-- and reversible by dropping the table.
--
-- Why a table rather than a naming convention: a redeemed invitation creates a
-- permanent member with no expiry. Without a record of who was a tester, ending
-- their access later depends on somebody remembering. This makes the revoke a
-- query rather than an act of memory.
-- ============================================================================

begin;

create table if not exists public.external_tester_access (
  id                bigint generated always as identity primary key,
  tester_name       text not null,
  tester_email      text not null,
  platform          text not null check (platform in ('ios', 'android', 'both')),
  intended_tier     membership_tier not null default 'member',
  invitation_id     bigint references public.invitation_codes(id),
  member_id         uuid references public.members(id),
  granted_at        timestamptz not null default now(),
  access_expires_at timestamptz not null,
  revoked_at        timestamptz,
  revoked_reason    text,
  notes             text,
  unique (tester_email, granted_at)
);

comment on table public.external_tester_access is
  'Temporary external tester access for the hiring trial. Internal only. Revoke with scripts/external-tester-revoke.sql.';

-- Internal only. Forced row level security with no policy denies every role
-- that is not the owner, regardless of any grant that might appear later.
alter table public.external_tester_access enable row level security;
alter table public.external_tester_access force row level security;

revoke all on table public.external_tester_access from public;
revoke all on table public.external_tester_access from anon;
revoke all on table public.external_tester_access from authenticated;
grant select, insert, update on table public.external_tester_access to service_role;

create index if not exists external_tester_access_active_idx
  on public.external_tester_access (access_expires_at)
  where revoked_at is null;

-- Fail closed: the table must not be reachable by an application role.
do $guard$
begin
  if has_table_privilege('anon', 'public.external_tester_access', 'SELECT')
     or has_table_privilege('authenticated', 'public.external_tester_access', 'SELECT') then
    raise exception 'external_tester_access is reachable by an application role';
  end if;
  raise notice 'external_tester_access created, internal only';
end;
$guard$;

commit;
