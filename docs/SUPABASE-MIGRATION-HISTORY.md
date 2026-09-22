# Supabase Migration History Guardrail

> **22 September 2026 — `20260921000001_p0_invitation_containment.sql` applied to production.**
> SHA-256 `38e3142ef20602ef82fb9b2e365b932bf0e6481399f58e876a3a2634e0e1bd39`, 27,290 bytes, applied
> via direct psql, exit 0. Expired all 1,216 valid unused invitations, raised the code generator to
> 192 bits, created nine replacements, bound redemption to `auth.uid()`, revoked anon and PUBLIC
> across the remediated surfaces, added `assert_aligned_map_access()` with server-side tier
> enforcement on the map functions, and changed default privileges for new functions in `public`.
> Rollback at `scripts/rollback-p0-invitation-containment.sql`, SHA-256
> `23b84826d204acf187630bc2dfb5ca739e52e29e3f1181ced227d3d62b80a5a0`. **Section 1 of that rollback
> must never be run**; it would revive the weak invitations. Full record in
> `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`.
>
> Known drift: production also carries `20260720000001_repair_degraded_feeds`, applied 20 July 2026,
> which exists only on the unpushed local branch `fix/repair-degraded-feeds`. Data only.


This repo must preserve every migration version recorded in the linked
production Supabase project. Do not delete old migration files from release
branches, even when the current schema has moved past them.

## What Happened

The remote database had historical migration versions that were missing from
the local release branch. Supabase correctly refused to push new migrations
until the local history matched production.

Most missing files were restored from Git history. The remote-only version
`20260406000001` could not be found in the available Git object graph, so it is
represented by `20260406000001_remote_history_marker.sql`, an intentional
no-op marker. This keeps history aligned without rewriting the remote migration
table or risking data loss.

## Release Rule

Before any store-bound build:

1. Run `npx supabase migration list`.
2. Confirm there are no remote-only migration versions.
3. Run `npx supabase db push --dry-run`.
4. Confirm only the intended new migration appears.
5. Apply with `npx supabase db push`.
6. Run `npm run verify:release`.

## Data Integrity Rule

Never use `supabase migration repair` to mark remote migrations reverted unless
the production database has been inspected and the team has explicitly decided
the remote version is wrong. Prefer restoring the missing local file. If the
original file is unrecoverable, add a clearly named no-op history marker and
document why.
