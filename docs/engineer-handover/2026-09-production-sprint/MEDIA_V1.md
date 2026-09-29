# Media V1

Media V1 is a core sprint deliverable. At commit `3ce4c4c` almost none of it exists. This file
states exactly what does, what is missing, and the decisions needed before building. It does not
choose a paid service; any new paid provider needs the owner's approval first.

## What exists

| Item | Evidence | Label |
|---|---|---|
| Enum `content_media_type` with `article`, `editorial`, `video`, `audio`, `digest` | `supabase/migrations/20260707000005_content_media_types.sql:12-17` | OBSERVED |
| Columns on `news_articles`: `media_type` (default `article`), `duration_seconds`, `format_meta` jsonb with example keys `thumbnail_url`, `hls_url`, `captions_url`, `stream_url`, `transcript_url` | Same file, lines 19-25 | OBSERVED |
| `get_news_feed` returns `media_type`, `duration_seconds`, `format_meta` | Same file and `20260718000001:151` | OBSERVED |
| Feed row shows a play or headphones badge on the thumbnail for video or audio | `components/pulse/ArticleRow.tsx:31-78` | OBSERVED |
| `expo-av ~16.0.8` in dependencies | `package.json` | OBSERVED, imported nowhere |
| Private `uploads` bucket with policies for `aligned-tiles/` only | `20260321000003:261-275` | OBSERVED |
| Image picking and upload helpers (tiles, projects, events) | `hooks/useCreateTile.ts`, `hooks/useCreateProject.ts`, `app/admin/events.tsx` | OBSERVED; two of three target the undefined `public` bucket (HO-09) |

Production at 5 Sep: zero storage objects, and every `news_articles` row an ingested article.

## Audio and podcast, item by item

| Capability | Exists? | Notes |
|---|---|---|
| Admin upload | No | No screen, no bucket path, no policy |
| Publish and unpublish | No | `news_articles.status` exists for articles; no media publish state or admin control |
| Metadata: title, description | Partial | `news_articles.title`, `snippet`, `summary` could hold them; these rows are pipeline articles with a source and URL, which fits media poorly |
| Artwork | Partial | `image_url` or `format_meta.thumbnail_url` |
| Duration | Schema only | `duration_seconds` |
| Authenticated access to the file | No | No media bucket, no signed URL code, no RPC |
| Playback, pause, seek, progress | No | No player component |
| Resume position | No | No table |
| Background audio and lock-screen controls | No | Needs `UIBackgroundModes: audio` on iOS and a foreground service on Android at prebuild; none configured |
| Loading and error states | No | |
| Member gating | No | Would need both an RPC or policy check and a bucket policy |
| Secure media URLs | No | |

## Video, item by item

| Capability | Exists? | Notes |
|---|---|---|
| Admin upload | No | |
| Publish and unpublish, delete | No | |
| Title, description, thumbnail | Schema only, as above | |
| Authenticated playback | No | |
| Controls, fullscreen | No | |
| Loading, buffering, errors | No | |
| Access control | No | |

## Platform and library notes

- `expo-av` is the older combined audio and video module. Expo has introduced `expo-audio` and `expo-video` as its successors and has deprecated `expo-av`; confirm its exact status for SDK 54 against the Expo changelog before building on it. Building Media V1 on `expo-av` risks a rewrite at the next SDK upgrade. Either successor needs a native build, which the Sentry work also needs, so both can share one store release.
- Background audio requires native configuration at prebuild, which cannot ship by OTA even if OTA were available.
- The ranking query is format-agnostic by design. Placing media rows in `news_articles` would put them into the same ranking, hide and save mechanics, and the same pipeline status values. That may be desirable or may not; it is a design decision (below).

## Storage and delivery

| Question | Current answer | Label |
|---|---|---|
| Which bucket | None for media | OBSERVED |
| Bucket security | `uploads` is private with folder-scoped policies; there is no media folder policy | OBSERVED |
| Signed URLs | Not used anywhere in the app (`createSignedUrl` absent); the app uses `getPublicUrl()` for images | OBSERVED |
| File-size limits | None set in migrations. Supabase plan limits on object size and the need for resumable uploads for large files are EXTERNAL VERIFICATION REQUIRED | |
| Current upload architecture | Client reads the file and uploads it in one request with the member JWT (`hooks/useCreateTile.ts:50-66`). Suitable for images; unsuitable for hundreds of megabytes on a mobile connection | OBSERVED |
| Streaming, transcoding, CDN | None integrated | OBSERVED |

## Suitability for longer-form video

**Current limitation.** Supabase Storage serves whole files. A single progressive MP4 served
through a short-lived signed URL plays on both platforms and supports seeking through HTTP range
requests, but it has one bitrate. There is no transcoding, no adaptive bitrate and no poster
generation.

**Why it matters.** A 30-minute 1080p file is typically several hundred megabytes. On a weak
mobile connection a single-bitrate stream stalls; members in markets with expensive data pay for
the full bitrate; egress cost scales with minutes watched multiplied by bitrate. Upload from a
phone of a file that size needs resumable upload.

**When it becomes necessary.** Short clips (under about five minutes) and audio are served
acceptably as files. Adaptive streaming becomes necessary when content is long, watched on mobile
data, or watched by enough members that egress cost matters. Measure egress per member-hour
before deciding.

**HLS on Supabase Storage specifically.** An HLS playlist references many segment files. A signed
URL covers one object, so a private HLS stream needs either signed URLs for every segment (the
playlist must be rewritten per viewer) or a delivery layer that authorises the whole path. This is
the technical reason private long-form video usually moves to a dedicated provider or a CDN with
token authentication.

**Options to assess, not decided.**

- Progressive MP4 in a private Supabase bucket, uploaded pre-encoded by an admin at a sensible bitrate, played through short-lived signed URLs. Lowest cost and effort; adequate for V1 with short content.
- Supabase Storage with HLS produced offline by the admin (for example with ffmpeg) and a per-viewer playlist rewrite in an Edge Function. No new vendor; more engineering; needs load testing.
- A managed video provider with transcoding, adaptive streaming and signed playback tokens. Least engineering for long-form; new monthly cost; new data processor for privacy declarations.
- Audio as MP3 or AAC files in a private bucket with signed URLs. Adequate at any realistic scale for this membership.

## Decisions needed before building

- Is Media part of the briefing (rows in `news_articles`) or a separate "Watch" and "Listen" surface with its own table? The second is easier to secure and to reason about.
- Which tiers see which media, and whether unpublished items are visible to admins only.
- Maximum length and file size for V1.
- Whether any paid provider is acceptable in this sprint (owner approval required).
- Whether background audio is required for V1 or desirable.

## Recommended V1 shape, subject to those decisions

A separate `media_items` table (type audio or video, title, description, artwork path, duration,
storage path, published flag, created by, timestamps) with RLS that lets active members of the
permitted tiers read published rows and lets admins do everything. A private `media` bucket with
policies that permit admin writes only and no direct member reads. A SECURITY DEFINER RPC that
checks membership and publish state and returns a signed URL with a short expiry. An admin screen
that uploads with resumable upload and writes the row. Member screens using `expo-audio` and
`expo-video`, with loading, buffering, error and "no longer available" states, and a small
progress table for resume. Negative tests: non-member and lower tier cannot obtain a signed URL,
cannot list the bucket, cannot read unpublished rows; an expired signed URL fails.
