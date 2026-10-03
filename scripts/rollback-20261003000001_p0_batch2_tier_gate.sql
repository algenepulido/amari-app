-- Rollback for 20261003000001_p0_batch2_tier_gate.sql. Restores prior (open) behaviour.
alter policy "Authenticated users can read project cache" on public.map_cache_projects using (true);
alter policy "Authenticated users can read state cache"   on public.map_cache_states   using (true);
alter policy "Authenticated users can read country cache" on public.map_cache_countries using (true);
alter policy "Users can read approved projects" on public.projects using (status = 'approved'::project_status);

create or replace function public.get_member_tier()
returns membership_tier language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_tier membership_tier;
begin
  select tier into v_tier from public.members where id = auth.uid() and status = 'active';
  if v_tier is not null then return v_tier; end if;
  begin
    v_tier := (auth.jwt() -> 'app_metadata' ->> 'tier')::membership_tier;
  exception when others then v_tier := null;
  end;
  return coalesce(v_tier, 'member'::membership_tier);
end;
$function$;

drop function if exists public.is_active_member_at_least(membership_tier);
