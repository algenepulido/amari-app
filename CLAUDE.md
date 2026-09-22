# AMARI Mobile — Claude Context

> ## Production security change, 22 September 2026
>
> A P0 invitation vulnerability was found live and **contained in production** on
> 2026-09-22T01:15Z. Invitation codes, invitation grants, the three map functions and
> function privileges all changed. **Read `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`
> before touching any of them.**
>
> The short version, because these will mislead you otherwise:
> the predictable bootstrap codes are all **expired** (1,216 of them, so 2,029 expired rows
> is correct, not corruption); new invite codes are **48 characters** after the prefix, not 8;
> `redeem_invitation_code` now binds to `auth.uid()` and refuses a mismatched `p_user_id`;
> `anon` and PUBLIC are revoked from redemption, the map trio and the rate limit pair, with
> `anon` retaining only `validate_invitation_code`; the map functions now enforce active
> membership at gold or above **server side**; and new functions in `public` no longer default
> to a PUBLIC grant.
>
> **Never run section 1 of `scripts/rollback-p0-invitation-containment.sql`** — it would revive
> all 1,216 weak invitations.


Read `AGENTS.md` first. It is the shared agent contract and it carries the
worktree layout, the operating rules, and the current list of known defects.
Then read `docs/AMARI-WORKING-MEMORY.md` for system state.

Three things that catch people out, repeated here because they are expensive:

- **Work in `C:\amari-ui-build`** (branch `release/v2-redesign-signed`). The
  OneDrive checkout sits on an older branch and does **not** contain the news
  feed, entity engine, or push system. Searching it will tell you those features
  do not exist.
- **Never edit app runtime code without explicit per-task approval from Tapiwa.**
  `app/`, `components/`, `lib/`, `hooks/`, `queries/`, `supabase/`, `app.json`.
  Reading is fine. Writing needs a yes, every time. Docs under `docs/` are fine
  when asked for.
- **PRs only.** Never commit directly to `release/v2-redesign-signed`.

The AMARI standard is to push beyond generic mobile UI while staying rigorous
about security, privacy, accessibility, and store compliance. Real data or an
honest empty state — never invent numbers, matches, or claims about what the app
did for a member.
