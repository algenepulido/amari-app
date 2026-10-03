-- P0 batch 2: tier-gated access and prompt privilege revocation (HO-01, HO-02, HO-08).
-- Owner decisions (2026-10-02): the map and projects are Gold and above (Gold, Platinum,
-- Laureate); a downgrade or suspension must take effect promptly rather than waiting for
-- the access token to refresh. Applies after 20261001000002.

-- Helper: is the caller an active member at or above a given tier. Reads the database,
-- never the JWT claim, so a stale token cannot satisfy it.
create or replace function public.is_active_member_at_least(p_min membership_tier)
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.members
    where id = auth.uid()
      and status = 'active'
      and public.tier_level(tier) >= public.tier_level(p_min)
  );
$$;
revoke execute on function public.is_active_member_at_least(membership_tier) from public;
grant execute on function public.is_active_member_at_least(membership_tier) to authenticated, anon;

-- HO-01: the three map cache tables were readable by any authenticated account (USING true).
-- Gate on an active Gold+ membership.
alter policy "Authenticated users can read project cache" on public.map_cache_projects
  using (public.is_active_member_at_least('gold'));
alter policy "Authenticated users can read state cache" on public.map_cache_states
  using (public.is_active_member_at_least('gold'));
alter policy "Authenticated users can read country cache" on public.map_cache_countries
  using (public.is_active_member_at_least('gold'));

-- HO-02: approved projects were readable by any authenticated account. Same Gold+ gate.
alter policy "Users can read approved projects" on public.projects
  using (status = 'approved'::project_status and public.is_active_member_at_least('gold'));

-- HO-08: get_member_tier fell back to the JWT app_metadata.tier claim for non-active
-- members, so a stale token kept an old tier after a downgrade. Read the tier only from
-- the database; a caller who is not an active member gets the base tier and no elevation.
-- (is_admin() already reads admin_roles joined to an active member row, from batch 1.)
create or replace function public.get_member_tier()
returns membership_tier language sql stable security definer set search_path to 'public'
as $$
  select coalesce(
    (select tier from public.members where id = auth.uid() and status = 'active'),
    'member'::membership_tier
  );
$$;
