# Release and rollback runbook

Commit `3ce4c4c`. Built from `docs/RELEASE-WORKFLOW.md` (reconciled 17 July 2026), `eas.json`,
`.github/workflows/`, `docs/eas-update.md` and the 22 September containment record. Where those
documents rely on the owner's machine, that is stated.

## The ground truth that shapes every release

- **No OTA.** Signed EAS Updates are configured but publishing is documented as blocked by the Expo plan (`docs/eas-update.md:3-9`). Treat every change, including JavaScript-only fixes, as a store release until the owner confirms otherwise. EXTERNAL VERIFICATION REQUIRED for the plan.
- **No staging.** A backend change reaches every installed version immediately.
- **Old binaries stay in the field.** Members do not update promptly. Any database change must keep the currently shipped 1.2.5 client working, as containment did by keeping the `redeem_invitation_code` signature.
- **One production owner.** Store submissions and production migrations are run by Jeremy unless he grants otherwise.

## JavaScript and application changes

- **Pre-release checks:** PR into `release/v2-redesign-signed`; CI green (lint, typecheck, security verifier, Jest, Deno, pgTAP); `npm run verify:release` (runs on push); device matrix rows for the touched journeys on both platforms using a preview or development build.
- **Build:** as a native change (below), because there is no OTA.
- **Rollback:** ship the previous commit as a new build with a higher build number. There is no instant revert.

## Native changes (new dependency, plugin, permission, SDK such as Sentry or media players)

- **Pre-release:** as above, plus `npx expo config --type public` review, and a check that required EAS environment variables exist for the production profile (Mapbox tokens are enforced by `app.config.js:9-19`).
- **iOS build:** `npm run release:ios:ci` (EAS production profile, remote credentials).
- **Android build:** run the GitHub Actions workflow "EAS Build" with profile `production`. Do not run `npm run release:android` locally; the documented result is an AAB signed with the wrong upload key.
- **Test:** install the TestFlight build and the Play internal or Alpha build; run the device matrix smoke rows.
- **Submission:** iOS with `npm run submit:ios`. Android submission to the `alpha` track needs the Play service-account key file, which lives only on the owner's machine (`docs/RELEASE-WORKFLOW.md`); otherwise upload the AAB through Play Console.
- **Staged release:** iOS phased release over seven days if enabled in App Store Connect; Play staged rollout percentage on production once Android reaches production (today it is closed testing only).
- **Post-release verification:** crash-free rate in the monitoring tool (once installed), App Store Connect and Play vitals, a sign-in on a fresh install from the store, push receipt on both platforms.
- **Rollback:** iOS cannot roll back a build; the options are to pause phased release, remove the version from sale in some cases, or expedite a fixed build through review. Play can halt a staged rollout and promote a previous release to the track; users who already updated keep the new version until a higher version code ships. Neither behaves like a server rollback.

## Database migrations

- **Pre-release:** migration in `supabase/migrations/` with the next timestamp; forward-only; replay-safe on an empty database (CI proves this); assertions that compare against counts captured at the start of the transaction, never against production numbers; a rollback script in `scripts/`; a pgTAP test in `supabase/tests/database/`. State the intended change and rollback to the owner before applying, as the brief requires.
- **Apply:** by the owner, in one transaction, with the file's SHA-256 recorded before and after, following `docs/P0_CONTAINMENT_DEPLOY_RUNBOOK.md` as the house pattern.
- **Post-apply:** read-only verification queries; grants checked with `has_function_privilege`; a member JWT smoke test.
- **Rollback limitations:** Supabase records applied migrations by version, so an edited file never re-runs; a rollback is a new forward migration or a reviewed rollback script. Data-changing migrations need a backup table first (containment kept 1,216 rows for this reason). Never run section 1 of `scripts/rollback-p0-invitation-containment.sql`, which would revive the expired weak invitations.
- **Compatibility:** a migration must not break 1.2.5 clients. Changing an RPC signature or a table the client reads directly (for example `map_cache_projects`) needs a two-step release: server change that tolerates both, then client, then cleanup.

## Edge Functions

- **Pre-release:** Deno tests (`deno test --allow-read --no-config supabase/functions`); review of the auth check.
- **Deploy:** `supabase functions deploy <name>`, with `--no-verify-jwt` for the pipeline functions as documented in `supabase/functions/NEWS-PIPELINE.md:13-17`. Deploying without the flag breaks the cron callers.
- **Rollback:** redeploy the previous commit's function. Deploys are immediate and global.

## iOS store build and Android store build in one release

Both need the same native changes, so combine Sentry and Media V1 players into one native release
where possible. Record each build's commit, build number, EAS build ID and artefact SHA-256 in
`docs/releases/` as was done for 1.2.5.

## Emergency response

- **Security issue in the database:** a forward migration revoking the grant or tightening the policy, applied by the owner; it takes effect for every client version at once.
- **Crash in a store build:** pause phased release or halt rollout; if the crash is triggered by server data, fix the data or the RPC first because that is instant.
- **Pipeline runaway spend:** the classifier has a hard monthly ceiling in code; to stop it immediately, unschedule the enrich cron job (`cron.unschedule`), which requires owner access.
- **Push storm:** unschedule the briefing cron job; the three-day cadence gate in `send-briefing-push` also limits repeats.
- **Compromised pipeline secret:** rotate `NEWS_PIPELINE_SECRET` in Edge Function secrets and `news_pipeline_secret` in Vault together, or triggers and crons fail silently.
