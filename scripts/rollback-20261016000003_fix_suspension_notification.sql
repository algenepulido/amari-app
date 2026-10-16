-- Rollback for 20261016000003. Restores admin_set_member_status to the version that writes the
-- status notification with type 'account_status'. Note that this restores the broken behavior:
-- that enum value does not exist, so the insert and the whole status change roll back. Run only
-- to undo the fix.

create or replace function public.admin_set_member_status(p_member_id uuid, p_status member_status, p_reason text default null::text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_actor uuid := auth.uid();
  v_old_status member_status;
  v_member_name text;
begin
  if v_actor is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  if not public.is_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized');
  end if;

  if p_member_id = v_actor then
    return jsonb_build_object('success', false, 'error', 'Admins cannot change their own account status');
  end if;

  select status, full_name
  into v_old_status, v_member_name
  from public.members
  where id = p_member_id;

  if not found then
    return jsonb_build_object('success', false, 'error', 'Member not found');
  end if;

  if v_old_status = p_status then
    return jsonb_build_object('success', false, 'error', 'Member already has this status');
  end if;

  update public.members
  set status = p_status,
      updated_at = now()
  where id = p_member_id;

  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) ||
    jsonb_build_object('member_status', p_status::text)
  where id = p_member_id;

  insert into public.notifications (member_id, type, title, body, data)
  values (
    p_member_id,
    'account_status',
    'Your AMARI account status changed',
    'Your account is now ' || initcap(p_status::text) || '.',
    jsonb_build_object(
      'old_status', v_old_status::text,
      'new_status', p_status::text,
      'reason', nullif(btrim(coalesce(p_reason, '')), ''),
      'changed_by', v_actor
    )
  );

  return jsonb_build_object(
    'success', true,
    'member_id', p_member_id,
    'member_name', v_member_name,
    'old_status', v_old_status::text,
    'new_status', p_status::text
  );
end;
$function$;
