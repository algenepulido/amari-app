# Access and environment requirements

For Algene Pulido. GitHub `algenepulido`. Google Play testing account `algene.pulido@gmail.com`.

Principles: invite him as a collaborator on each platform under his own identity, never share an
account password, grant the least role that does the job, and separate what he needs to
investigate from what he needs to ship. Status values are READY, NEEDS USER ACTION, NEEDS EXTERNAL
PLATFORM ACCESS, NOT CURRENTLY AVAILABLE, UNKNOWN / MUST VERIFY.

## The environment question comes first

There is no staging project. `eas.json:13,31,50` point development, preview and production builds at
the same Supabase project. The authorisation work in this sprint consists mostly of calls that must
fail; running them against production is possible for read-only denials but unsafe for anything
that could succeed. Three options exist; the owner must choose.

| Option | What it is | Cost and effort | Fit |
|---|---|---|---|
| Local Supabase from migrations | `supabase db start` in Docker. CI already does this on every push | Free. The schema replays (CI proves it at `3ce4c4c`). No production data, no Vault secret, no cron, no Storage objects, no Auth provider config | Best for SQL-level negative tests and pgTAP. Cannot test Apple or Google sign-in end to end |
| Separate staging Supabase project | New project, migrations applied, Edge Functions deployed, providers configured | Plan-dependent; EXTERNAL VERIFICATION REQUIRED. Needs Apple and Google redirect URLs added | Best for device testing against a realistic backend. Needs an app build pointed at it, which means a new EAS profile |
| Supabase branching | Preview branches of the production project | Plan-dependent; EXTERNAL VERIFICATION REQUIRED | Similar to staging with less setup, if the plan includes it |
| Production, read-only | Negative tests that can only be refused, run with real member JWTs | No cost | Acceptable for denials only, with the owner's agreement, never for writes |

Recommendation: local Supabase for SQL authorisation work from day one, and one staging project
for device and auth-provider work if the owner approves the cost. Production only for read-only
denials agreed in advance.

## Access matrix

| Service | Why needed | Minimum role | Needed immediately? | Current status | Who actions | Security note |
|---|---|---|---|---|---|---|
| GitHub `amari-app` | Code, branches, PRs, CI results | Collaborator with Write; branch protection on `release/v2-redesign-signed` requiring PR review | Yes | NEEDS USER ACTION. Repository has one collaborator | Jeremy, repository settings | Do not grant Admin. Actions secrets stay owner-only |
| GitHub Actions secrets | Not needed to investigate. Needed only if he must change the signed Android workflow | None; owner runs `eas-build.yml` | No | Owner-only | Jeremy | `ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `EXPO_TOKEN`, `EXPO_PUBLIC_MAPBOX_TOKEN` must not be shared |
| Supabase production project | Read schema, policies, grants, cron, logs, Storage config; confirm plan, backups, PITR, pooling | Organisation member with a read-only or developer role. Supabase role names and their exact rights are EXTERNAL VERIFICATION REQUIRED | Yes, read-only | NEEDS USER ACTION | Jeremy, Supabase dashboard | No service-role key by email or chat. No database password. SQL editor use should be read-only unless agreed |
| Supabase staging or local | Negative tests, migration rehearsal | Owner of the staging project, or local Docker | Yes | NOT CURRENTLY AVAILABLE (staging); local is READY from the repository | Jeremy decides; Algene builds | Seed synthetic data only |
| Supabase Edge Function secrets | Confirm names present, rotate if needed | Owner | No | UNKNOWN / MUST VERIFY | Jeremy | Values never leave the dashboard |
| Expo / EAS | Build logs, build profiles, environment variables, submissions | Expo organisation member with Developer role, if the project is under an organisation. It is under a personal account per `docs/releases/1.2.5-artifacts.md`; a personal account cannot add members | For builds, yes | UNKNOWN / MUST VERIFY | Jeremy | Moving the project into an Expo organisation may be needed to grant access without sharing the account |
| Apple App Store Connect | TestFlight installs; release metadata; phased release | TestFlight external or internal tester for investigation; App Manager only if he submits | Tester: yes. Submission: no | NEEDS EXTERNAL PLATFORM ACCESS. The 5 Sep report records an Individual developer account, which cannot add team members | Jeremy | If the account is Individual, he can only be a TestFlight tester or use the public App Store build. Owner submits |
| Google Play Console, testing | Install the closed-test build | Add `algene.pulido@gmail.com` to a closed-testing list on the Alpha track and send the opt-in link | Yes | NEEDS EXTERNAL PLATFORM ACCESS | Jeremy | Invited is not opted in; he must accept the link. He also counts towards the 12-tester production gate |
| Google Play Console, release | Staged rollout, pre-launch report, vitals | User with release permissions scoped to this app | No, only for release | NEEDS EXTERNAL PLATFORM ACCESS | Jeremy | Do not grant account-wide admin |
| Sentry or chosen monitor | Create project, DSN, source maps | Member of a new organisation or project owned by AMARI | When observability starts, day 2 or 3 | NOT CURRENTLY AVAILABLE. No account is referenced anywhere except a placeholder in `.env.example` | Jeremy approves cost; Algene sets up | A paid tier needs owner approval |
| Mapbox | Download token for native builds; usage and cost | Own download-scoped token, or build via the owner's EAS secret | For local native builds only | UNKNOWN / MUST VERIFY | Jeremy | Never share the owner's secret token; issue a scoped token |
| Push infrastructure | Expo push service uses the EAS project credentials; APNs key and FCM credentials live in EAS | Covered by EAS access | With EAS | UNKNOWN / MUST VERIFY | Jeremy | Credentials stay in EAS |
| Apple Sign In configuration | Services ID, key, redirect URLs in Supabase Auth | Read-only view of Supabase Auth providers | For auth work | UNKNOWN / MUST VERIFY | Jeremy | The Apple key and team identifiers are credentials |
| Google Cloud OAuth clients | Web, Android and iOS client IDs, SHA-1 fingerprints, redirect URIs | Viewer on the Google Cloud project | For auth work | UNKNOWN / MUST VERIFY | Jeremy | Client secret never shared |
| Website `amarigroupau.com` | Hosts `/auth-callback` used by OAuth fallback and magic links | Read access to the page source or repository | For deep-link work | UNKNOWN / MUST VERIFY | Jeremy | |
| Email delivery for OTP | Deliverability of sign-in codes | Visibility of Supabase Auth SMTP settings | For auth work | UNKNOWN / MUST VERIFY | Jeremy | |
| Classifier provider | Only if he touches the pipeline | None | No | Not needed yet | | Keys stay in Supabase secrets |
| Vault | `news_pipeline_secret` used by pg_net triggers | None | No | | | Presence can be checked by name without reading the value |

## Investigation access against release access

| Needed to investigate and fix | Needed only to release |
|---|---|
| GitHub Write | Play Console release permissions |
| Supabase read-only on production | App Store Connect App Manager, or the owner submits |
| Local or staging Supabase with full control | EAS submit rights |
| TestFlight tester, Play closed tester | GitHub Actions run permission for `eas-build.yml` |
| EAS read access to builds and env | Supabase migration apply rights on production |
| Test identities and invitation codes on the target environment | |

Recommendation: the owner applies production migrations and runs store submissions during this
sprint, with Algene preparing the PR, the migration, the rollback and the verification queries.
That keeps privileged credentials with one person while the engineer still does the work.
