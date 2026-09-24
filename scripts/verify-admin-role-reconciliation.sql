with by_role as (
  select role::text as role, count(*) as holders
  from public.admin_roles
  group by role
),
via_admin_invite as (
  select count(distinct a.member_id) as n
  from public.admin_roles a
  join public.invitation_codes i on i.used_by = a.member_id
  where coalesce(i.grants_admin, false) or i.staff_role_grant is not null
),
via_predictable_admin_invite as (
  select count(distinct a.member_id) as n
  from public.admin_roles a
  join public.invitation_codes i on i.used_by = a.member_id
  where (coalesce(i.grants_admin, false) or i.staff_role_grant is not null)
    and coalesce(i.code, '') ~ '^AMARI-[A-Z]{3,4}-[0-9]{3}$'
),
no_admin_invite as (
  select count(*) as n
  from public.admin_roles a
  where not exists (
    select 1 from public.invitation_codes i
    where i.used_by = a.member_id
      and (coalesce(i.grants_admin, false) or i.staff_role_grant is not null)
  )
)
select 'by role' as section, role as subject, holders::text as value from by_role
union all
select 'total', 'admin_roles_rows', (select count(*)::text from public.admin_roles)
union all
select 'reconciliation', 'admins_who_redeemed_an_admin_capable_invite',
       (select n::text from via_admin_invite)
union all
select 'reconciliation', 'of_those_via_a_predictable_format_code',
       (select n::text from via_predictable_admin_invite)
union all
select 'reconciliation', 'admins_with_no_admin_capable_invite_redemption',
       (select n::text from no_admin_invite)
order by 1, 2;
