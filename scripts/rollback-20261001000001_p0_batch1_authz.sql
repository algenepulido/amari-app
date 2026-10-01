-- Rollback for 20261001000001_p0_batch1_authz.sql. Restores the prior behaviour of all three objects.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path to 'public'
as $$ select exists (select 1 from public.admin_roles where member_id = auth.uid()); $$;

drop trigger if exists tr_enforce_project_status_authority on public.projects;
drop function if exists public.enforce_project_status_authority();

create or replace function public.rsvp_to_event(p_event_id bigint, p_member_id uuid default null::uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_actor uuid := auth.uid(); v_event public.events%rowtype; v_member public.members%rowtype; v_existing public.event_rsvps%rowtype; v_current_count int; v_status rsvp_status;
begin
  if v_actor is null then return jsonb_build_object('success', false, 'error', 'Not authenticated'); end if;
  if p_member_id is not null and p_member_id <> v_actor then return jsonb_build_object('success', false, 'error', 'Cannot RSVP on behalf of another member'); end if;
  select * into v_event from public.events where id = p_event_id for update;
  if not found then return jsonb_build_object('success', false, 'error', 'Event not found'); end if;
  if v_event.starts_at <= now() then return jsonb_build_object('success', false, 'error', 'This event has already started'); end if;
  select * into v_member from public.members where id = v_actor and status = 'active';
  if not found then return jsonb_build_object('success', false, 'error', 'Member not found or inactive'); end if;
  if public.tier_level(v_member.tier) < public.tier_level(v_event.min_tier) then return jsonb_build_object('success', false, 'error', 'Tier too low for this event'); end if;
  if v_event.early_access_at is not null and now() < v_event.early_access_at then return jsonb_build_object('success', false, 'error', 'RSVPs not yet open'); end if;
  if v_event.general_access_at is not null and now() < v_event.general_access_at and public.tier_level(v_member.tier) < public.tier_level('platinum'::membership_tier) then return jsonb_build_object('success', false, 'error', 'Early access for Platinum+ only'); end if;
  select * into v_existing from public.event_rsvps where event_id = p_event_id and member_id = v_actor;
  if found and v_existing.status <> 'cancelled' then return jsonb_build_object('success', false, 'error', 'Already RSVPd'); end if;
  if v_event.capacity is not null then
    select count(*) into v_current_count from public.event_rsvps where event_id = p_event_id and status = 'confirmed';
    if v_current_count >= v_event.capacity then v_status := 'waitlisted'; else v_status := 'confirmed'; end if;
  else v_status := 'confirmed'; end if;
  if found then
    update public.event_rsvps set status = v_status, checked_in_at = null, checked_in_by = null where id = v_existing.id;
  else
    insert into public.event_rsvps (event_id, member_id, status) values (p_event_id, v_actor, v_status);
  end if;
  return jsonb_build_object('success', true, 'status', v_status::text, 'event_title', v_event.title);
end; $function$;
