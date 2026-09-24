# AMARI Mobile Security Hardening Roadmap

> **Correction, 22 September 2026.** Two claims below were wrong when written and are still wrong.
>
> The line under Current Security Foundations saying invite-code validation sits behind
> "hash lookup and rate limiting" is **false**. The rate limit was removed on 4 May 2026 by
> `20260504000007_invite_validation_rate_limit_fix.sql`, six days after this document was written,
> and was never replaced. `check_rate_limit` is now revoked from all application roles and is called
> from nowhere. Anonymous abuse limiting on `validate_invitation_code` remains **outstanding**.
>
> The P0 standard stated further down, that functions accepting user identifiers must prove
> `auth.uid()` matches, was **not** met by `redeem_invitation_code` until 22 September 2026. It is
> met now. See `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`.


Last updated: 2026-04-28

## Goal

Make AMARI materially difficult to compromise on iOS and Android while reducing
the blast radius if any one control fails. No mobile app can guarantee that
personal information "never leaks", but the target standard is:

- sensitive data is never trusted to client-side checks alone
- data access is authorized in Postgres with RLS and hardened RPCs
- high-risk requests are tied to a signed-in user and a legitimate app instance
- personal data collection is minimized, classified, retained only while useful,
  and removable
- every security boundary has an automated regression test

Use OWASP MASVS as the verification baseline, especially storage, auth, network,
platform interaction, code quality, resilience, and privacy controls.

## Current Security Foundations

- Expo/Supabase app with Supabase session persistence through `expo-secure-store`
  in `lib/supabase.ts`.
- Invite-code validation moved behind hash lookup and rate limiting in
  `20260302000001_security_hardening.sql`.
- Later authority hardening in
  `20260321000003_authority_hardening_v2.sql` locks down client-supplied member
  IDs for key RPCs, removes direct access to barcode seeds, and restricts several
  privileged function grants.
- App already supports email OTP fallback, Google auth, Apple auth, and
  deep-link callback handling.
- EAS Update is configured by runtime version and platform-specific update
  scripts.

## P0: Close Server-Side Data Leaks First

These are the highest-value changes because attackers can reverse engineer a
mobile app, but they should not be able to bypass server authorization.

1. Add a Supabase security regression test suite.
   - Test as `anon`, normal member, higher-tier member, admin, and service role.
   - Assert every exposed `public` table has RLS enabled.
   - Assert `anon` cannot select member, invite, event RSVP, barcode, onboarding,
     or admin data.
   - Assert members can only read/update their own profile fields.
   - Assert admin-only functions fail for non-admins.
   - Assert `barcode_seeds`, `rate_limits`, and future internal tables are not
     readable by `anon` or `authenticated`.

2. Add SQL function boundary tests.
   - Every `SECURITY DEFINER` function must set `search_path`.
   - Functions that accept member/user IDs must prove `auth.uid()` matches or
     require admin/service role.
   - Privileged functions must explicitly revoke from `public` and `anon`.
   - Sensitive functions should return low-detail errors to avoid enumeration.

3. Add a privacy/data map.
   - Classify each field: public profile, member-only profile, sensitive member
     metadata, operational secret, or audit-only.
   - Define retention for invite attempts, onboarding responses, logs, uploads,
     push tokens, account deletion requests, and admin audit logs.
   - Do not collect precise location, identity documents, financial account
     details, or exact net worth/investment capacity unless there is a legal and
     product reason.

4. Harden onboarding storage before collecting new data.
   - Store archetype answers in a dedicated table, not loosely in `members`.
   - Let users read and update only their own onboarding row.
   - Admins should see either aggregate analytics or explicitly audited member
     detail views.
   - Store free text separately and treat it as sensitive. Prefer structured
     choice data over open text.

## P1: Add App Integrity Gates

Client-side checks are useful only when the backend verifies them. The app should
earn a device/app trust level, and the server should use that trust level to
decide what actions are allowed.

1. Android: integrate Play Integrity API.
   - Use Standard API requests for sensitive actions.
   - Bind each verdict to request data with `requestHash`.
   - Verify verdicts on a Supabase Edge Function or backend service, not in the
     app.
   - Start in observe-only mode, then enforce for invite redemption, onboarding
     submission, profile updates, RSVP, barcode generation, and admin actions.
   - Use tiered responses: allow, allow with limits, require reauth, deny.

2. iOS: integrate Apple App Attest.
   - Generate per-user/per-device App Attest keys on supported devices.
   - Server issues a one-time challenge and verifies attestation/assertions.
   - Store only the key identifier, counters, last successful assertion time, and
     risk status.
   - Gracefully degrade on unsupported devices, but rate-limit or step-up risky
     actions.

3. Add a `device_installations` table.
   - `id`, `user_id`, `platform`, `app_version`, `build_number`,
     `attestation_provider`, `attestation_status`, `last_seen_at`,
     `risk_level`, `revoked_at`.
   - RLS: user can read their own devices; admin access is audited.

4. Add an `app_integrity_events` table.
   - Record failed verdicts, replay attempts, rooted/jailbroken/emulator signals,
     and mismatched app builds.
   - Do not store raw attestation blobs longer than necessary.

## P2: Token, Auth, and Session Hardening

1. SecureStore configuration.
   - Keep Supabase tokens in SecureStore on native only.
   - Review whether `keychainAccessible` should be set to a stricter class for
     iOS token storage.
   - Use biometric/local-auth step-up only for high-risk actions; do not block
     normal token refresh with biometrics unless UX is intentionally strict.

2. Supabase Auth settings.
   - Enable MFA for admins, editors, and door staff first.
   - Consider optional MFA for high-tier members.
   - Use reasonable session controls: inactivity timeout, maximum session
     lifetime, and possibly single-session for admin accounts.
   - Keep JWT expiry conservative; Supabase recommends not going below 5 minutes.

3. Admin access.
   - Require `aal2` for admin routes once MFA is enabled.
   - Add server-side admin audit logs for member reads, tier changes, invite-code
     creation, content publishing, and account deletion handling.
   - Add an admin session age check before destructive actions.

4. Account lifecycle.
   - Make deletion/export flows real and auditable.
   - On deletion: revoke sessions, delete push tokens, remove onboarding/free text
     where required, anonymize retained operational records where full deletion
     would break accounting/audit integrity.

## P3: Transport, Updates, and Supply Chain

1. EAS Update code signing.
   - Enable end-to-end code signing for OTA updates when plan support allows it.
   - Store the private signing key outside source control.
   - Add release checks that unsigned production updates cannot be published.

2. Dependency and build controls.
   - Add `npm audit --audit-level high` or a curated advisory gate.
   - Add dependency review for PRs.
   - Generate an SBOM for native releases.
   - Keep Expo SDK, React Native, Mapbox, Supabase, and auth libraries current.

3. Production logging.
   - Remove production `console.log`.
   - Scrub PII from `console.error`, Sentry breadcrumbs, and network errors.
   - Never log invite codes, OTPs, access tokens, refresh tokens, email links,
     App Attest challenges, Play Integrity tokens, or Supabase service errors
     containing SQL details.

4. Privacy manifests and store declarations.
   - Maintain Apple `PrivacyInfo.xcprivacy` for collected data and required
     reason APIs.
   - Keep App Store privacy labels and Google Play Data Safety aligned with the
     actual fields collected by onboarding and profile features.

## P4: Resilience Against Reverse Engineering and Device Compromise

These controls raise cost but do not replace server-side authorization.

- Enforce release-only builds for stores; disable debuggable flags and WebView
  debugging in production.
- Enable Android minification/obfuscation where Expo/EAS supports it.
- Strip source maps and symbols from public artifacts.
- Use jailbreak/root/emulator/debugger signals only as risk inputs, not as sole
  deny reasons.
- Consider screenshot/screen-recording protection for membership card, QR pass,
  admin screens, and onboarding free-text review screens.
- Avoid certificate pinning directly against Supabase/third-party APIs unless
  AMARI owns the backend/proxy and can rotate pins safely.

## Security Regression Tests to Add

1. `npm run verify:security`
   - Runs static checks for forbidden secrets, localhost redirects, production
     logs, and unsafe SecureStore/localStorage usage.
   - Added 2026-04-28. Also runs onboarding security assertions.

2. `npm run test:rls`
   - Starts Supabase locally, seeds users, and verifies RLS/RPC boundaries.

3. `npm run test:onboarding-security`
   - Verifies onboarding answers can be inserted/read by the owner only.
   - Verifies admin aggregate views do not leak free text or emails.
   - Added 2026-04-28 as a static SQL boundary gate. Full local Supabase
     execution still needs Docker Desktop available.

4. Release verifier additions.
   - Ensure Apple auth, Google auth, auth callback bridge, EAS runtime version,
     Mapbox attribution, and update scripts remain configured.
   - Add checks for App Attest/Play Integrity feature flags once implemented.
   - Added 2026-04-28: `npm run verify:release` now runs
     `npm run verify:security`, checks the post-auth onboarding route, and
     blocks production EAS Update scripts unless code signing is configured.

## 2026-04-28 Implemented Controls

- Added `member_onboarding_responses`,
  `member_onboarding_evidence_ledger`, and `member_onboarding_snapshots`.
- Onboarding writes go through `submit_member_onboarding`, which derives the
  actor from `auth.uid()` and never accepts a client-supplied member ID.
- Direct client writes to onboarding tables are revoked; members can only read
  their own response/snapshot.
- The evidence ledger has no direct authenticated client policies or grants.
- `members.onboarded_at` is protected by the privileged-field trigger and may
  only be set by the onboarding RPC context.
- Admin aggregates enforce a minimum cohort of 20 and do not return member IDs,
  emails, names, or free text.
- Production EAS Update scripts fail closed until Expo code signing metadata and
  certificate path are configured.
- `npm audit fix --package-lock-only --audit-level=high` removed all high
  severity npm audit findings without changing top-level package versions.

## Implementation Order

1. Add onboarding schema with strict RLS and tests before shipping the new
   onboarding UI.
2. Add security regression scripts and make them part of `verify:release`.
3. Add admin MFA and admin audit logging.
4. Add Play Integrity and App Attest in observe-only mode.
5. Turn on enforcement for high-risk RPCs after measuring false positives.
6. Enable EAS Update code signing.
7. Schedule an OWASP MASVS-focused external pentest before public scaling.

## Primary References

- OWASP MASVS: https://mas.owasp.org/MASVS/
- Android Play Integrity API:
  https://developer.android.com/google/play/integrity/overview
- Android Keystore:
  https://developer.android.com/privacy-and-security/keystore
- Apple App Attest:
  https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity
- Apple runtime sandboxing:
  https://support.apple.com/en-gw/guide/security/sec15bfe098e/web
- Apple Keychain data protection:
  https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/1/web/1
- Expo SecureStore:
  https://docs.expo.dev/versions/latest/sdk/securestore/
- EAS Update code signing:
  https://docs.expo.dev/eas-update/code-signing/
- Supabase RLS:
  https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase MFA:
  https://supabase.com/docs/guides/auth/auth-mfa
- Supabase sessions:
  https://supabase.com/docs/guides/auth/sessions
- Apple privacy manifests:
  https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
