# P0 invitation containment, deployed 22 September 2026

**Authoritative record of a production security change.** Read this before touching invitations,
invitation codes, the map functions, function grants, or anything under `supabase/migrations`.

Applied to production **2026-09-22T01:15:06Z**, committed `01:15:09Z`, exit code 0. Migration
`supabase/migrations/20260921000001_p0_invitation_containment.sql`, SHA-256
`38e3142ef20602ef82fb9b2e365b932bf0e6481399f58e876a3a2634e0e1bd39`, 27,290 bytes.

> **Amended 24 September 2026, after deployment.** The file on disk is now SHA-256
> `120016c798cb9e2ab7aa0f29b9c877a4afe18690f56f0428d9c2cd3dee8209c1`, 27,697 bytes. The hash above
> remains the record of what actually executed against production and is not superseded.
>
> The map smoke test raised `no administrator exists to run the map smoke test as` whenever
> `public.admin_roles` was empty. Production held four administrators so it ran there, but a
> freshly built database has no seed data, so the migration could not replay and CI failed on
> every run. The smoke test now skips with a notice in that case and is otherwise unchanged.
>
> Production is unaffected. Supabase records applied migrations by version, so the amended file
> will not re-run. Wherever administrators exist the smoke test still runs and still rolls the
> migration back if the guard is wrong.

> **The sibling migration needed the same treatment.**
> `supabase/migrations/20260922000002_short_codes_and_validation_throttle.sql` asserted
> `member count changed to %, expected 23` and an administrator count of 4. Those were correct as
> a guard on a production run and wrong as migration invariants, for the same reason: a freshly
> built database has neither. It now captures both counts at the start of its transaction and
> asserts they are unchanged at the end, which holds on production and on an empty database alike.
> It ran against production as SHA-256
> `d6f2b58b19bc29d2773a567f2a8bcabbcff2353932218f4e2f7d68139abc0841`, 8,557 bytes, and the file is
> now `3340ac057fed10b8114fd4d883e931737db914aec3a119546df1d8600ad3ee36`, 9,601 bytes.
>
> The containment migration already compared against a captured baseline rather than fixed
> numbers, which is why its membership assertions needed no change.

## Why this happened

Production had a complete path from an unauthenticated stranger to an `admin_roles` row.

- The bootstrap invitation pool was inserted from **literal predictable values** at
  `20260323000001_membership_invites_and_moderation.sql:962`. Twelve of those codes granted admin
  at laureate tier. The pattern was two fixed prefixes plus a three digit counter.
- `validate_invitation_code` was SECURITY DEFINER **granted to anon with no rate limit** after
  `20260504000007` removed the limit and never replaced it. `check_rate_limit` was called from
  nowhere in the live schema.
- `redeem_invitation_code` was SECURITY DEFINER, executable by **PUBLIC and anon** in production,
  and accepted a caller-supplied `p_user_id` that it never compared to `auth.uid()`. It inserted
  into `admin_roles` and wrote `is_admin` into auth metadata.
- `public.is_admin()` reads `admin_roles`, so every admin policy and RPC then passed.

The repository was also **public** at the time, so the code pattern was published alongside the
project reference and the anon key. The repository was made private on 21 September 2026.

Verified live before the fix: 1,216 valid unused invitations, 9 admin-capable, 1,209 predictable or
bootstrap. All four existing administrators had arrived through that same bootstrap path, which was
the expected shape rather than evidence of intrusion.

## What the migration did

One transaction. Nothing deleted. No redeemed invitation altered.

- **Expired every valid unused invitation**, 1,216 of them, capturing each prior expiry into
  `public.invitation_expiry_backup_20260921` first so rollback can restore exact values.
- **Raised the code generator** `generate_share_invite_code` from `gen_random_bytes(4)` to
  `gen_random_bytes(24)`. That is 32 bits to **192 bits**, hex encoded to a 48 character suffix.
- **Created nine replacement invitations** for the nine pending addressed recipients, with the
  secrets generated inside the transaction. `invite_source = 'reissue'`, `grants_admin = false`,
  `staff_role_grant` null, single use, explicit expiry, tier preserved.
- **Bound redemption to `auth.uid()`.** `redeem_invitation_code` keeps its signature so clients
  already in the field keep working, but `p_user_id` is now an assertion rather than an authority:
  it must equal `auth.uid()` or the call returns `identity_mismatch`. It fails closed with
  `not_authenticated` when there is no session.
- **Revoked anon and PUBLIC** from `redeem_invitation_code`, `check_rate_limit`,
  `cleanup_rate_limits` and the three map functions. `authenticated` also revoked from the two rate
  limit functions.
- **Added `public.assert_aligned_map_access()`** and rewrote `map_projects`, `map_states` and
  `map_countries` to call it. They now enforce, server side, an authenticated caller with an active
  member row at gold tier or above, or an administrator. A fixed `search_path = public, extensions`
  was also set on all three.
- **Changed default privileges** so newly created functions in `public` are not granted to PUBLIC.
  Existing functions were deliberately left alone.

## The state you will find in production now

| Measure | Before | After |
|---|---|---|
| Valid unused invitations | 1,216 | **9**, all `invite_source = 'reissue'` |
| Valid unused admin-capable | 9 | **0** |
| Valid unused bootstrap or predictable | 1,209 | **0** |
| Valid unused with a weak random component | 1,216 | **0** |
| Rows in `invitation_codes` | 2,053 | 2,062 |
| Unused but expired | 813 | 2,029 |
| Members | 23 | 23 |
| `admin_roles` | 4, one owner and three admins | unchanged |
| Redeemed invitations | 24 | 24 |
| Backup rows for rollback | 0 | 1,216 |

Schema-wide, as a consequence of the named changes only: definer functions reachable by `anon` fell
from 16 to 11, by PUBLIC from 15 to 10, those without a fixed `search_path` from 8 to 5, and
anon-callable ones with no `auth.uid()` check from 13 to 8.

## Things that are now false and will mislead you

- **The bootstrap codes work.** They do not. All 1,216 are expired. `AMARI-MEMB-001` style codes are
  dead. 2,029 expired rows is the expected state, not corruption.
- **Anyone can call the map RPCs.** No. `anon` is revoked and the functions enforce active
  membership at gold or above.
- **`redeem_invitation_code` takes the user id you pass.** It validates it against `auth.uid()` and
  refuses a mismatch.
- **Invite codes are eight characters after the prefix.** New ones are **48**. Anything that assumes
  the old length is wrong. The shipped client imposes no length or pattern limit, verified at
  `app/(auth)/invite.tsx:44` and `components/v2/Onboarding.tsx:308`, which check only a minimum of
  four characters.
- `docs/SECURITY-HARDENING-ROADMAP.md:25` still claims invite-code rate limiting is a current
  foundation. It is not, and was not at the time it was written. Rate limiting remains Phase 2.

## Traps

- **Never run section 1 of `scripts/rollback-p0-invitation-containment.sql`.** It restores the old
  expiries and would revive all 1,216 weak invitations. Section 2, the grants, is what you want if a
  client breaks. Section 5 restores the vulnerable redemption function and exists only for
  completeness.
- **`invitation_expiry_backup_20260921` is internal.** Forced RLS, no policy, revoked from `public`,
  `anon` and `authenticated`, granted only to `service_role`. Do not expose it.
- **Do not reintroduce a PUBLIC grant.** Default privileges now prevent it for new functions in
  `public`, but `create or replace` on an existing function preserves that function's existing ACL.
- **Absence of a GRANT does not mean unreachable.** Postgres grants EXECUTE to PUBLIC on creation
  and this schema has no blanket revoke. Audit what is **revoked**, not what is granted.

## Outstanding, Phase 2, not blocking

- Invitation codes are still stored in plaintext in `invitation_codes.code`, on all 2,062 rows.
- `validate_invitation_code` remains anon-callable with **no rate limiting**. It is a valid or
  invalid oracle. The 192-bit codes make brute force infeasible, which is why this was acceptable to
  defer, but it still needs a trustworthy caller key.
- The Apple private relay branch in `redeem_invitation_code` tests the shape of a caller-supplied
  string rather than the authentication provider, so it can bypass the recipient email binding.
- Ten definer functions still hold a PUBLIC grant and need a reviewed allow-list pass, one at a
  time, each with a test.
- Aligned tier gating: `lib/theme.ts` enforces level 3, which is **gold**, while the on-screen copy
  in `app/(tabs)/aligned/_layout.tsx` says "Available from Platinum membership". The migration
  reproduced the enforced rule, gold, so nothing that worked stopped working. Which one is correct
  is a product decision, not a security one.
- Production carries migration `20260720000001_repair_degraded_feeds`, applied 20 July 2026, that
  exists only on an unpushed local branch `fix/repair-degraded-feeds`. Data only, touches no grant,
  policy or function, but it is drift and should be committed to the release line as a record.

## Not yet done

**The nine replacement codes have not been distributed.** They are valid, unused and unexpired. Four
physical iPhone acceptance tests must pass first: one onboarding with a 48 character code, Aligned
map access as gold or above, admin panels plus a tier change, and confirmation that member and
silver are refused the map.

## Evidence

- `docs/evidence/DEPLOYMENT_RECORD.md`, completed record with every count and control.
- `docs/evidence/before-20260922T011456Z-statement-one.csv`, paired before grid.
- `docs/evidence/after-20260922T011536Z-statement-one.csv`, paired after grid.
- `docs/evidence/after-20260922T011536Z-admin-reconciliation.csv`.
- `docs/P0_INVITATION_CONTAINMENT_PLAN.md`, design, threat model and object-by-object analysis.
- `docs/P0_FIXTURE_FIDELITY_MANIFEST.md`, how the test fixture was proven faithful to production.
- `scripts/verify-production-reviewer-prerequisites.sql`, the read-only verification script.
- `supabase/verification/p0/p0_invitation_containment.test.sql`, 45 assertions.
- `supabase/verification/p0/`, production-faithful fixture and the authorisation matrix.

## Lessons worth keeping

- **A fixture that diverges from production does not test the thing being deployed.** Two fixtures
  passed while production could not run the same migration: one declared `invitation_codes.id` as
  `uuid` where production has `bigint`, and one omitted the `members` display id trigger entirely.
- **Inside a SECURITY DEFINER function, `current_user` is the owner, not the caller.** A
  `pg_has_role(current_user, ...)` check there is true for every caller and silently admits every
  tier. The tier matrix caught it; reading the code had not.
- **When a count looks wrong, make the database assert it.** A false drift alarm came from counting
  lines in a psql capture that still carried the row-count footer. `-t` suppresses both header and
  footer.
- **A gate that has only ever passed is not known to work.** `scripts/verify-security.mjs` scans only
  client directories and has never looked at `supabase/migrations`, which is where all of this lived.
