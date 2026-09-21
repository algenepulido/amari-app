# Production reviewer prerequisite verification

Prepared 21 September 2026 against commit `d51fe55`. Companion script:
`scripts/verify-production-reviewer-prerequisites.sql`.

## Evidence labels

Every claim in this document carries one of four labels.

**VERIFIED LIVE** means observed in the production database. Nothing in this document carries
that label yet, because the script has not been run.

**VERIFIED REPOSITORY** means read from the repository at the commit named above, with a file
and line reference. It says what the code intends. It is not evidence of live behaviour.

**INFERRED** means reasoned from verified facts without direct observation of either.

**NOT TESTED** means no observation has been made and none is claimed.

Code inspection is never used as evidence of live behaviour anywhere in this document. That
distinction is the reason the script exists.

## How to run the script

Open the Supabase SQL Editor on the production project. The file contains two statements,
separated by a comment banner. The editor returns the result of the last statement only, so run
them one at a time: highlight statement one, run it, copy the whole grid, then do the same for
statement two.

Statement two reads the Supabase migration ledger and is kept separate deliberately. If it
fails because that schema is absent or unreadable, that failure is itself a finding, and
statement one is unaffected. Report the error text rather than rows.

The script was validated before being handed over. It was executed against a disposable local
Postgres instance loaded with a fixture that reproduces the shapes it inspects. Both statements
ran, and the fixture confirmed the detection logic fires rather than merely returning zero: it
correctly reported an admin-capable unused code in a predictable format, a definer function with
no search path, and the default public execute grant. The container was destroyed afterwards. No
production system was contacted.

### What the script guarantees

It contains no INSERT, UPDATE, DELETE, ALTER, DROP, CREATE, GRANT, REVOKE, TRUNCATE or COMMENT
statement, and calls no function that changes state. It returns no invitation code, no code hash,
no email address, no member personal information, no token and no secret. The plaintext code
column is read inside a pattern predicate so that predictable formats can be counted, and its
value never reaches the output.

## A. Verified facts

### Verified repository

- The live bootstrap invitation pool is inserted from literal, predictable values, two fixed
  prefixes plus a three digit counter, at
  `supabase/migrations/20260323000001_membership_invites_and_moderation.sql:962`. Twelve of the
  inserted rows carry an administrative grant at laureate tier. Expiry was set to one year from
  23 March 2026. VERIFIED REPOSITORY.
- `validate_invitation_code` is security definer and granted to the anonymous role, with no rate
  limit, at `supabase/migrations/20260504000007_invite_validation_rate_limit_fix.sql:36`. The
  migration that removed the limit did not replace it. VERIFIED REPOSITORY.
- `check_rate_limit` is called from nowhere in the current migration set. VERIFIED REPOSITORY.
- `redeem_invitation_code` accepts `p_user_id uuid` from the caller and never compares it with
  `auth.uid()`, at `supabase/migrations/20260521000002_retire_duplicate_member_invites.sql:3`. It
  is granted to the authenticated role at line 134, inserts into `admin_roles` at line 102, and
  writes `is_admin` into authentication metadata at line 112. VERIFIED REPOSITORY.
- The Apple private relay exception at line 60 of the same file tests the shape of a
  caller-supplied string and does not establish the authentication provider. VERIFIED REPOSITORY.
- `public.is_admin()` reads `admin_roles`, at
  `supabase/migrations/20260321000003_authority_hardening_v2.sql:28`. VERIFIED REPOSITORY.
- There is no blanket revoke and no altered default privileges anywhere in the fifty four
  migrations, so any function never named in a revoke keeps the Postgres default of execute to
  public. VERIFIED REPOSITORY.
- `scripts/verify-security.mjs:5` scans six client directories and has never scanned
  `supabase/migrations`. VERIFIED REPOSITORY.

### Verified repository, secret hygiene

This section is complete, because it needs no database.

| File path | Type of credential | Tracked by git | Action required |
|---|---|---|---|
| `.env.example` | placeholder template, no live material | yes | no |
| `certs/certificate.pem` | public code signing certificate, no private key present | yes | no |
| `eas.json` | Supabase anonymous key, client facing by design | yes | no, but see note |
| `.github/workflows/setup-keystore.yml` | signing password accepted as an unmasked workflow input, keystore uploaded as an artefact | yes | yes |
| `scripts/verify-mobile-flows.mjs` | a live production invitation code and a named person's email address, in plain text | yes | yes |
| `docs/TINASHE-ANDROID-TEST-SCRIPT.md` | the same invitation code and email address | yes | yes |
| `supabase/seed.sql` | four literal invitation codes, one granting laureate tier with administrative rights | yes | yes, confirm this file has never been applied to production |

Further verified repository facts about secrets.

- No service-role key has ever been committed. Every object in the full history was enumerated,
  1,973 objects and 1,606 named blobs, and the 851 text blobs among them were scanned for JWT
  shaped strings. Every such string was decoded and its role claim read. Exactly one JWT has ever
  been committed, in `eas.json`, and its role claim is `anon`. No value was printed. VERIFIED
  REPOSITORY.
- No private key material of any kind has ever been added. A pickaxe search across all 207
  commits for the PEM headers of RSA, EC, OpenSSH and PKCS8 private keys returned nothing.
  VERIFIED REPOSITORY.
- Every occurrence of `service_role` and `SUPABASE_SERVICE_ROLE_KEY` in the current tree is a
  reference rather than a value: a scanner pattern, a grant statement, a policy predicate, or a
  `Deno.env.get` call in an edge function. VERIFIED REPOSITORY.
- No `.p8`, `.p12`, `.jks`, `.keystore`, `.mobileprovision`, `google-services.json`,
  `GoogleService-Info.plist` or service-account JSON is tracked in HEAD or was ever added in
  history. VERIFIED REPOSITORY.

The note on `eas.json` is that committing an anonymous key is normal, since it ships inside the
binary and is public by design. It is recorded here because it is the credential an attacker uses
to reach the anonymous role, so its existence is part of the exposure even though it is not a
leak.

### Action taken, repository visibility

On 21 September 2026, on explicit instruction, the repository was set to private. This is the one
action taken in this phase. It touched no credential, no database object and no history.

Verified rather than assumed. Unauthenticated requests now return 404 at all three surfaces:
`raw.githubusercontent.com` for a previously public file, `api.github.com` for the repository, and
`github.com` for the repository page. The GitHub API reports `visibility=private`.

It does not undo prior exposure. Anything already read or mirrored while the repository was public
remains outside our control. It stops continued public access while the live state is established.

### Verified repository, exposure surface

This was checked after the tables above were written, and it changes how every row in them should
be read. The earlier assessment did not establish repository visibility and should not have
characterised exposure without it.

- **The repository `tapiwanashenyerenyere-afk/amari-app` is public.** Visibility is `public` and
  `private` is false. There is one collaborator, no fork, no deploy key and no watcher. VERIFIED
  REPOSITORY, read from the GitHub API on 21 September 2026.
- The migration carrying the predictable administrative invitation pool is present on the public
  default branch `master`, and the administrative insert is in that public copy. Anyone may read
  it without authenticating. VERIFIED REPOSITORY.
- `supabase/seed.sql`, carrying four literal codes including one granting laureate tier with
  administrative rights, is on the public default branch. VERIFIED REPOSITORY.
- `eas.json`, carrying the Supabase project reference and the anonymous key, is on the public
  default branch. VERIFIED REPOSITORY.
- `scripts/verify-mobile-flows.mjs` and `docs/TINASHE-ANDROID-TEST-SCRIPT.md`, carrying the live
  silver invitation code and a named person's email address, are not on `master` but are present
  on nineteen pushed branches, every one of which is public. VERIFIED REPOSITORY.

The consequence is that the predictable code pattern is not merely guessable. It is published,
together with the project reference and the anonymous key needed to reach the endpoint. No
guessing is required for any of it.

### Verified repository, keystore workflow exposure

- The keystore workflow has been run exactly once, on 27 February 2026, dispatched by the account
  owner. VERIFIED REPOSITORY.
- The `android-keystore` artefact from that run exists in the record and is expired. It expired on
  28 February 2026 and cannot be downloaded now. VERIFIED REPOSITORY.
- The run logs are no longer retrievable. The GitHub API returns HTTP 410 Gone for them. VERIFIED
  REPOSITORY.
- During the window in which they were live, both were public, because the repository is public.
  The artefact carried the keystore and its base64 encoding. The log carried the password on the
  `keytool` command line, because the input is typed as a string and is therefore not masked.
  INFERRED from the workflow definition and the repository visibility, not from any access record.
- Whether anybody retrieved either is unknowable from here. GitHub does not expose access logs for
  this. NOT TESTED and not testable by us.

- Declared artefact retention was one day, at `.github/workflows/setup-keystore.yml:42`. The
  keystore is JKS, alias `amari-key`, validity 10000 days. VERIFIED REPOSITORY.
- The repository secrets `ANDROID_KEYSTORE_BASE64` and `KEYSTORE_PASSWORD` were created at
  02:02:54 and 02:02:58 on 27 February 2026, and neither has been updated since. The workflow run
  began at 02:02:24 and produced its artefact at 02:02:33. VERIFIED REPOSITORY, read from the
  GitHub API. Secret names and timestamps only; no value was read or is readable.

Reading those timestamps together, the keystore that was published as a public artefact is almost
certainly the same keystore now held in `ANDROID_KEYSTORE_BASE64`, and the password that was typed
as an unmasked workflow input is almost certainly the one now held in `KEYSTORE_PASSWORD`. Twenty
one seconds separate the artefact from the secret. Neither has been rotated in the seven months
since. INFERRED, on timestamp evidence, not verified by comparing material, which cannot be done
without reading the secret.

The alias and store type match the upload keystore recorded in the project's own release notes, so
this is the upload key rather than Google's app signing key. INFERRED. Whether Play App Signing is
enabled, which determines how cheaply an upload key can be reset, is a Play Console question and
remains NOT TESTED.

The practical reading is that the Android upload key and its password should be treated as
potentially compromised, with no evidence of actual retrieval either way. That is a judgement about
posture rather than a finding of compromise.

### Verified live

None yet. This section is filled from the script output.

## B. Static findings not yet proven live

Each item below is VERIFIED REPOSITORY and NOT TESTED against production. The metric that will
settle each one is named, so the script output can be read directly against this list.

| Static finding | Settled by | Confirms the risk when |
|---|---|---|
| Predictable admin codes are still usable | `1.10 VALID_UNUSED_PREDICTABLE_AND_ADMIN_CAPABLE` | above zero |
| Any admin-capable invitation remains open | `1.06 valid_unused_admin_capable` | above zero |
| The March bootstrap reset did expire the old pool | `1.07 expired_unused_admin_capable` | a large number here with zero at 1.06 is the reassuring shape |
| Some admin codes were already redeemed | `1.08 redeemed_admin_capable` | above zero means an admin account exists that was created this way, which should be reconciled against known administrators |
| Plaintext codes are still stored in the table | `1.05 rows_where_plaintext_code_column_not_null` | above zero |
| Validation is anonymously callable | `3.10` row for `validate_invitation_code`, field `anon` | true |
| Redemption is callable by any authenticated user and ignores `auth.uid()` | `3.10` row for `redeem_invitation_code`, fields `authenticated` and `auth_uid` | authenticated true and auth_uid false |
| No rate limiting is in force | section `3.30`, and `check_rate_limit` grants at `3.10` | only `check_rate_limit` appears, and nothing calls it |
| Definer functions keep the default public grant | `2.02 secdef_executable_by_public` | materially above the number of functions intended to be public |
| Anonymous callers reach definer functions with no identity check | `2.06 secdef_anon_callable_without_auth_uid` | above zero |
| The map functions are readable by anonymous callers | `3.10` rows for `map_projects`, `map_states`, `map_countries` | anon true |
| Definer functions without a search path | `2.05 secdef_without_search_path` | above zero |
| Tables without row level security | `4.01 tables_without_rls` | above zero, then read the `4.10` rows |

## C. Live and repository discrepancies

NOT TESTED. This section is filled after the script runs.

Three comparisons will be made, and all three are mechanical rather than impressionistic.

The set of security definer functions live, from section `2.10`, against the set derived from
parsing all fifty four migrations. The migration-derived set contains seventy security definer
functions. Any function present live and absent from the migrations indicates a change applied
outside version control. Any function present in the migrations and absent live indicates a
migration that never reached production.

The live grant on each function, from sections `2.10` and `3.10`, against the grant the
migrations intend. This is the comparison that matters most, because grants are the control that
the static inspection could only partly settle.

The applied migration ledger from statement two against the fifty four filenames in
`supabase/migrations`. A version applied that is not in the repository, or a repository migration
never applied, is drift.

The `body_md5` values in section `3.10` establish a baseline fingerprint for the high risk
functions. They prove nothing on their own today. They allow a later run to show whether a
function body changed, which is the cheapest possible tamper check.

## D. Immediate P0 concerns

**The invitation path to administrative control.** VERIFIED REPOSITORY, NOT TESTED live. The
chain is anonymous enumeration of predictable admin codes, then redemption by any authenticated
caller, then an `admin_roles` row.

A precision that matters. A valid unused admin-capable code does not by itself prove that a
stranger can become an administrator. It establishes a precondition. Complete exploitability also
depends on the validation function being anonymously callable in the live database, on the
redemption function behaving as its source says, and on no server-side check intervening that the
source does not show. None of those is proven live. The correct posture is to treat the path as
P0 until it is disproven, not to describe it as an open door.

What raises the urgency is the exposure surface rather than the code alone. The pattern is not
guessable, it is published on a public repository together with the project reference and the
anonymous key, so the only unknown in the chain is the live database state. Row `1.10` settles
the first link.

**Redemption trusting caller-supplied identity.** VERIFIED REPOSITORY. This is a defect
regardless of the code pool, because it lets a member row and an administrative role be bound to
an identifier the caller chose. It also violates the standard the project set for itself at
`docs/SECURITY-HARDENING-ROADMAP.md:55`.

**A live invitation code committed in plain text.** VERIFIED REPOSITORY. It is silver tier, not
administrative, and it should be expired whether or not it has been redeemed, because publication
in a repository is not reversible by deletion.

**The keystore workflow.** VERIFIED REPOSITORY. The signing password is an unmasked input and the
keystore is uploaded as an artefact. Anyone with read access to that workflow run can retrieve
both halves.

## E. Things that are safe

- No service-role key and no private key has ever been committed. VERIFIED REPOSITORY.
- The committed Supabase key is the anonymous key, confirmed by decoding its role claim. VERIFIED
  REPOSITORY.
- `change_member_tier` requires `is_admin()` before changing any tier, and refuses to act on
  behalf of another member. VERIFIED REPOSITORY.
- The members table policy set is self-read and self-update, with administrative access separate,
  and a trigger rejects direct updates to privileged member fields. VERIFIED REPOSITORY.
- `admin_create_invitation_code` refuses to create an administrative or staff invitation at all.
  VERIFIED REPOSITORY.
- `get_aligned_tile_contact_details` gates on active membership, tile approval, an explicit
  contact opt-in and tier visibility before returning an owner email. VERIFIED REPOSITORY.
- No email provider, SMTP path or email edge function exists, so no reviewer action could email a
  real member. VERIFIED REPOSITORY.
- Edge functions read the service key from the environment rather than holding it. VERIFIED
  REPOSITORY.

## F. Things still unknown

- Every live fact. Nothing has been observed in production. NOT TESTED.
- Whether `supabase/seed.sql` has ever been applied to the production project. If it has, it adds
  a further administrative code. NOT TESTED.
- Whether the twelve administrative bootstrap codes have been redeemed, and if so by whom. The
  script answers the count at `1.08`; reconciling those against known administrators is a separate
  step and needs care, because it touches identity.
- Whether production contains database objects that no migration in the repository describes.
  Statement two and section `2.10` together answer this. NOT TESTED.
- Whether a suspended member is refused by the database, given the client guard reads status and
  does not act on it. NOT TESTED, and not covered by this script, because proving it needs a real
  user token rather than catalogue metadata.
- Whether the Apple provider can be read server side from `auth.identities`. This is the linchpin
  of Apple-only reviewer activation and it is INFERRED from how Supabase stores identities, not
  verified anywhere in this repository. It needs a negative test, not a catalogue query.

## G. Recommended remediation order

This is a recommendation and nothing has been actioned. Credential rotation and history rewriting
are explicitly deferred until the live state is understood, on the principle that you cannot
sensibly rotate what you have not yet established is operationally significant.

Before any of the ordered steps, one decision stands on its own. The repository is public, and
making it private is a single reversible setting that immediately reduces the exposure of the
invitation pool, the seed codes, the tester code and the personal email address, without touching
any credential, any database object or any history. It does not repair anything, and it does not
undo publication that has already occurred, but it stops the clock. It is the cheapest action
available and it is yours to take or decline.

First, run the script and read `1.10` and `1.06`. Everything else waits on those two numbers.
Run `secure-output/targeted-code-checks.sql` alongside it, which answers whether the specific
codes committed in the repository are still live, and whether the seed file has ever reached
production. That file is gitignored because it contains code values. Its output contains none, so
the output is safe to paste back.

Second, if either is above zero, expire the administrative bootstrap rows. This is a single
update that sets expiry on rows already identified by their source and grant, it deletes nothing,
and it is reversible in the sense that history is preserved. It closes the open door without
touching any other control.

Third, if the targeted check shows it is still live, expire the invitation code committed in the
repository. Only then remove it from `scripts/verify-mobile-flows.mjs` and
`docs/TINASHE-ANDROID-TEST-SCRIPT.md`, along with the personal email address. Removing it from the
current files does not remove it from history, and on a public repository it does not remove it
from anywhere it has already been read. Expiring the code is the control. Editing the files is
hygiene, and rewriting history is a separate decision that should not be taken while the live
state is still unknown.

Alongside that, decide on the signing material. The artefact and the logs are no longer
retrievable, so there is no continuing exposure to close, only a judgement about the window that
has already passed. If Play App Signing is enabled for this application, resetting the upload key
is a contained operation that does not require republishing under a new key, which makes rotation
cheap. Confirming whether it is enabled is the next question, and it is a Play Console question
rather than a repository one.

Fourth, repair `redeem_invitation_code` so that it binds to `auth.uid()` and ignores any
caller-supplied identifier, and condition the Apple relay exception on an actual Apple identity
rather than on the shape of a string.

Fifth, restore rate limiting on validation, keyed per caller rather than in one shared anonymous
bucket, which was the flaw that caused the original limit to be removed rather than fixed.

Sixth, revoke the default public execute grant from the definer functions that do not need it,
starting with `check_rate_limit` and the three map functions, and adopt an explicit revoke and
grant for every function so that the default never decides anything again.

Seventh, extend `scripts/verify-security.mjs` to scan `supabase/migrations`, and give it a case
that must fail, so the class of defect that produced this document cannot recur silently.

Only after those are closed should the reviewer environment be built, and it should still be
built as a separate Supabase project rather than inside production.

## What happens next

Nothing further proceeds until the script output exists. Paste the two grids back and this
document gets its VERIFIED LIVE section, section C gets the three comparisons, and the
recommendation in section G either stands or is withdrawn on the evidence.
