# Open questions for Jeremy

Only questions that need owner knowledge, owner decisions or platform access. Everything else is
answered, or marked for Algene to verify, elsewhere in the pack.

## Access

- Will you invite `algenepulido` to GitHub with Write, and protect the release branch?
- Which Supabase role will you grant, and do you accept that he should hold no service-role key?
- Is the Expo project under a personal account or an organisation? If personal, will you create an organisation so he can be added without sharing the account?
- Is the Apple developer account still Individual? If so, he can be a TestFlight tester only.
- Will you send the 5 September readiness report PDF privately?

## Production

- Where may negative tests run: local only, a new staging project (cost to be approved), or read-only denials on production?
- May a member-tier identity for Algene exist on production for device smoke tests? Any higher tier or admin identity on production shows him real member data; do you approve that, and until when?
- How many invitations have been issued since 22 September, and to whom (counts only, for the register)?

## Apple

- Is phased release enabled for App Store updates?
- Which storefronts are live now, and is the absence of Nigeria and other markets deliberate?
- Who submits builds during the sprint: you, or Algene with App Manager access?

## Google

- What is the current opted-in tester count on the Alpha track?
- Has developer verification (due 30 September 2026) been completed?
- Is Play App Signing enabled for `com.amari.mobile`?

## Supabase

- Which plan is the project on? Are daily backups and point-in-time recovery available?
- Is email and password sign-in enabled (for reviewer accounts)? Is general sign-up enabled, and should it be closed at the Auth level given the app is invitation-only?
- Does a storage bucket named `public` exist?
- Are the legacy anon and service-role keys still enabled alongside the new key system?

## Media

- Is Media a separate "Watch" and "Listen" surface or part of the briefing?
- Which tiers may play which media?
- What is the longest audio episode and the longest video you intend to publish in the first three months, and their typical file sizes?
- Is any paid media provider acceptable in this sprint, and at what monthly ceiling?
- Is background audio required for V1?

## Security

- Aligned boundary: the enforced rule is gold and above; the in-app copy says Platinum. Which is correct?
- Should a suspended administrator lose admin rights immediately (recommended)?
- Apple Hide My Email: should recipient-addressed invitations still be redeemable through a relay address?
- Should `scripts/verify-mobile-flows.mjs`, `docs/*-ANDROID-TEST-SCRIPT.md` (a tester script whose file name carries a first name) and `supabase/seed.sql` be scrubbed of code-shaped strings now that the repository is private?

## Product decisions

- Event capacity: should cancelling a ticket promote the first waitlisted member automatically?
- Aligned reporting and blocking: is a report action required before wider launch?
- Corridor: keep hidden, remove, or schedule?
- Should silver members see a reduced Aligned (for example the project directory without the map)?

## Legal and compliance

- Account deletion: automated deletion after a grace period, or a staffed process with a stated response time?
- Existing members without a consent record: re-consent prompt, or another approach?
- Who owns App Privacy and Data safety declarations if Sentry and media storage are added?

## Operations

- Where should pipeline and cron alerts go (email address or admin push)?
- Who is on call if a store build misbehaves during the sprint?
- May Algene request an unschedule of the enrich or briefing cron jobs in an emergency, and through whom?
