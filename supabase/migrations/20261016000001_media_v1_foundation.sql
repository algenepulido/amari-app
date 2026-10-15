-- Media V1 foundation. A dedicated media surface, separate from the news/article
-- feed, so it is easy to secure and reason about. Two-layer tier access, matching
-- the pattern already approved and used for Pulse editorial: every active member
-- sees the catalog (what exists, and which tier unlocks it), but the media file
-- itself is only handed out, as a short-lived signed URL, to members at or above
-- the item's min_tier. The playable file stays in a private bucket, and its
-- storage path is never exposed to a member who is not entitled to play it.
--
-- This migration is the data layer only: the table, its RLS, the private bucket
-- and its policies, and the two SECURITY DEFINER RPCs the app calls. The signed
-- URL is minted by an edge function that calls request_media_playback with the
-- member's JWT and, only on an "allowed" result, signs the returned path with the
-- service role. Playback gating is proven in p0_media_v1_access.test.sql.

begin;

-- 1. The media catalog table.
create table if not exists public.media_items (
  id uuid primary key default gen_random_uuid(),
  media_type public.content_media_type not null,
  title text not null,
  description text,
  artwork_path text,
  storage_path text not null,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  min_tier public.membership_tier not null default 'gold',
  published boolean not null default false,
  created_by uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint media_items_media_type_check check (media_type in ('audio', 'video'))
);

create index if not exists idx_media_items_published
  on public.media_items(published, created_at desc);

-- 2. RLS. Members never touch this table directly; they go through the two RPCs
-- below, so the only direct policy is for admins. This keeps storage_path out of
-- any member-reachable query. The table grant is explicit so the behavior is the
-- same whether or not the toolchain auto-grants the authenticated role.
alter table public.media_items enable row level security;

grant select, insert, update, delete on public.media_items to authenticated;

drop policy if exists "media_items_admin_all" on public.media_items;
create policy "media_items_admin_all" on public.media_items
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 3. Private media bucket. Admin writes only; there is no member read policy at
-- all, so a member cannot list or fetch an object directly. Members only ever
-- receive a short-lived signed URL, minted by the edge function with the service
-- role, which bypasses these policies.
insert into storage.buckets (id, name, public)
values ('media', 'media', false)
on conflict (id) do update set public = false;

drop policy if exists "media_bucket_admin_select" on storage.objects;
drop policy if exists "media_bucket_admin_insert" on storage.objects;
drop policy if exists "media_bucket_admin_update" on storage.objects;
drop policy if exists "media_bucket_admin_delete" on storage.objects;

create policy "media_bucket_admin_select" on storage.objects
  for select to authenticated
  using (bucket_id = 'media' and public.is_admin());
create policy "media_bucket_admin_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'media' and public.is_admin());
create policy "media_bucket_admin_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'media' and public.is_admin())
  with check (bucket_id = 'media' and public.is_admin());
create policy "media_bucket_admin_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'media' and public.is_admin());

-- 4. Catalog RPC. Every active member sees the published catalog, with enough to
-- render it and show which tier unlocks each item, but never the storage path.
create or replace function public.get_media_catalog()
returns table (
  id uuid,
  media_type text,
  title text,
  description text,
  artwork_path text,
  duration_seconds integer,
  min_tier text
)
language sql
security definer
set search_path to 'public'
as $$
  select m.id, m.media_type::text, m.title, m.description, m.artwork_path,
         m.duration_seconds, m.min_tier::text
  from public.media_items m
  where m.published = true
    and public.is_active_member()
  order by m.created_at desc;
$$;

-- 5. Playback authorization RPC. Returns the storage path only when the caller is
-- an active member at or above the item's min_tier. Admins bypass the tier and the
-- published checks. An unpublished item reports the same not_found as a missing one
-- so its existence does not leak. The edge function turns an "allowed" result into
-- a signed URL.
create or replace function public.request_media_playback(p_media_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_actor uuid := auth.uid();
  v_tier public.membership_tier;
  v_status text;
  v_is_admin boolean;
  v_media public.media_items%rowtype;
begin
  if v_actor is null then
    return jsonb_build_object('allowed', false, 'error', 'not_authenticated');
  end if;

  v_is_admin := public.is_admin();

  select tier, status into v_tier, v_status
  from public.members where id = v_actor;

  if (v_tier is null or v_status <> 'active') and not v_is_admin then
    return jsonb_build_object('allowed', false, 'error', 'not_member');
  end if;

  select * into v_media from public.media_items where id = p_media_id;
  if not found then
    return jsonb_build_object('allowed', false, 'error', 'not_found');
  end if;

  if not v_is_admin then
    if not v_media.published then
      return jsonb_build_object('allowed', false, 'error', 'not_found');
    end if;
    if public.tier_level(v_tier) < public.tier_level(v_media.min_tier) then
      return jsonb_build_object('allowed', false, 'error', 'tier_too_low',
                                'required_tier', v_media.min_tier::text);
    end if;
  end if;

  return jsonb_build_object(
    'allowed', true,
    'storage_path', v_media.storage_path,
    'media_type', v_media.media_type::text,
    'title', v_media.title,
    'duration_seconds', v_media.duration_seconds
  );
end;
$$;

-- 6. Grants. Members reach media only through these two functions.
revoke all on function public.get_media_catalog() from public, anon;
revoke all on function public.request_media_playback(uuid) from public, anon;
grant execute on function public.get_media_catalog() to authenticated;
grant execute on function public.request_media_playback(uuid) to authenticated;

commit;
