-- Rollback for 20261016000001. Removes the Media V1 data layer: the two RPCs, the
-- storage policies, the private media bucket (only when it holds no objects), and
-- the media_items table (its RLS policy, grants and index drop with it). Run only
-- to undo that migration.

begin;

drop function if exists public.request_media_playback(uuid);
drop function if exists public.get_media_catalog();

drop policy if exists "media_bucket_admin_select" on storage.objects;
drop policy if exists "media_bucket_admin_insert" on storage.objects;
drop policy if exists "media_bucket_admin_update" on storage.objects;
drop policy if exists "media_bucket_admin_delete" on storage.objects;

-- The private media bucket is left in place: direct deletion from storage.buckets
-- is blocked by Supabase's storage protection trigger, and an empty bucket with no
-- policies is inert. Remove it through the Storage API or the dashboard if desired.

drop table if exists public.media_items;

commit;
