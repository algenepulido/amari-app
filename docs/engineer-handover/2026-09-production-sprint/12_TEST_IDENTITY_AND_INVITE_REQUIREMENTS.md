# Test identity and invitation requirements

Nothing here has been created. No credentials appear in this pack. Each identity below belongs to
Algene alone, so that every action is attributable, and each is revoked at the end of the sprint.

## Decide the environment before creating anything

On production, any identity at gold or above sees the names, employers and project details of
real members, and an admin identity sees everything. The provisioning script itself warns about
this (`scripts/reviewer-account-provision.sql`, "Tier, and why the default is the low one"). Creating
identities on production is therefore a privacy decision as well as an access decision.

| Environment | Consequence for identities |
|---|---|
| Local Supabase (Docker) | Algene creates every identity himself from seed SQL. No real data. Cannot exercise Apple or Google sign-in end to end |
| Staging project | Owner or Algene creates identities; synthetic members only. Needs a staging app build for device tests |
| Production | Owner creates identities. Real members visible to gold and above, and to admin. Every write is a production write |

Recommendation: full identity set on local or staging. On production, at most one member-tier
identity for device smoke tests of sign-in and store builds, unless the owner decides otherwise
in writing.

## Existing tooling

| Tool | What it does | Touches production? |
|---|---|---|
| Admin Codes screen, `app/admin/codes.tsx`, via `admin_create_invitation_code` | Issues a single invitation at a chosen tier. Refuses admin and staff grants (`20260710000002:78`) | Yes, when used in the production app |
| `scripts/external-tester-issue.sql` | Issues personal invitations from a gitignored CSV, tracks them in `external_tester_access`, refuses platinum and laureate unless overridden, never grants admin | Yes, run with psql against production. Requires `20260922000001` applied |
| `scripts/external-tester-revoke.sql` | Suspends the tester's member row so the database refuses them | Yes |
| `scripts/reviewer-account-provision.sql` | Prepares the member side of a password account the owner creates in the Auth dashboard; default tier member; dry run by default | Yes |
| Admin Members screen, `app/admin/members.tsx`, via `change_member_tier` and `admin_set_member_status` | Changes tier and suspends | Yes |
| `supabase/seed.sql` | Local seed including literal codes | Local only. Never run against production |

There is no tooling that creates an administrator. `admin_roles` is written only by
`redeem_invitation_code`, and every issuing path now refuses admin invitations, so an admin test
identity on any shared environment requires a deliberate SQL insert by the owner.

## Identities

### Active normal member
- **Required state:** auth user, member row `status = active`, tier `silver` (the entry tier most new members will hold), onboarded.
- **Expected permissions:** Pulse, briefing, events, own profile, issue reports, deletion request.
- **Expected denials:** Aligned tab and every Aligned data path (map RPCs, `map_cache_*` tables, projects), admin RPCs, other members' rows.
- **Exists:** No.
- **Provision safely:** invitation at silver from the Admin Codes screen or `external-tester-issue.sql`; Algene redeems it on a device with his own sign-in.
- **Touches production:** only if issued there.
- **Never:** use it to browse real members' data if the tier is later raised.

### Lower-tier member
- **Required state:** as above at tier `member`.
- **Expected denials:** as silver, plus silver-gated tables (`city_presence` directory, `corridor_opportunities`, tile creation).
- **Exists:** No. **Provision:** invitation at member tier. **Touches production:** if issued there.

### Higher-tier member
- **Required state:** tier `gold` minimum for Aligned; `platinum` to test early event access windows.
- **Expected permissions:** Aligned map and directory, project creation, introductions, early event access at platinum.
- **Expected denials:** admin RPCs, others' private rows, self-approval of projects.
- **Exists:** No.
- **Provision:** invitation at gold, then `change_member_tier` to platinum when needed. On production this exposes real member data; prefer staging.
- **Never:** export, screenshot or copy real member data seen through this identity.

### Admin
- **Required state:** active member plus an `admin_roles` row with role `admin`.
- **Expected permissions:** admin screens and RPCs, `pipeline` Edge Functions via admin JWT, check-in, moderation.
- **Expected denials:** none inside the app; the database owner role remains separate.
- **Exists:** Four administrator roles exist on production (1 owner, 3 admin at 22 Sep). None belongs to Algene.
- **Provision:** on local or staging, insert the `admin_roles` row in seed SQL. On production, only by the owner, deliberately, with an expiry date recorded in `external_tester_access` or a note.
- **Never:** change a real member's tier or status, issue invitations to real people, publish Pulse content, or run check-in against a real event.

### Suspended or inactive member
- **Required state:** member row `status` not `active` (use the value set by `admin_set_member_status`), previously active so it holds a session and an old JWT.
- **Expected denials:** every member RPC and table; the admin bypass must also fail if the account was an admin (HO-07).
- **Exists:** No.
- **Provision:** create an active member, sign in on a device to keep a session, then suspend via the Admin Members screen or `external-tester-revoke.sql`.
- **Touches production:** if done there.
- **Never:** suspend a real member to test this.

### Admin capable of publishing Media
- **Required state:** admin as above.
- **Exists:** No, and no Media publishing workflow exists yet (see `13`). This identity becomes useful once Media V1 has an upload path.
- **Provision:** reuse the admin identity; on production only after the Media V1 design is approved.

### Two fresh invitation codes
- **Required state:** two unused, unexpired invitations at member or silver tier, addressed to Algene's own email addresses or unaddressed, created after 22 Sep so they use the six-character format.
- **Provision:** Admin Codes screen or `external-tester-issue.sql`. The script expects one live invitation per email, so two codes need two addresses or two runs after redemption.
- **Delivery:** send each code through a channel separate from the email that names the account, and never in a chat transcript; invitation 2068 had to be expired on 22 Sep after its code was pasted into one.
- **Touches production:** yes, if issued there.

## Secure handoff table

For Jeremy to complete outside this repository copy, or in a private note. Record only whether
each item was supplied and how, never the credential or code itself.

| Item | Environment | Supplied? | Date | Channel used | Expiry or revoke date | Notes |
|---|---|---|---|---|---|---|
| Active normal member (silver) | | | | | | |
| Lower-tier member (member) | | | | | | |
| Higher-tier member (gold or platinum) | | | | | | |
| Admin | | | | | | |
| Suspended member | | | | | | |
| Media publishing admin | | | | | | |
| Invitation code one | | | | | | |
| Invitation code two | | | | | | |

## Revocation at sprint end

Suspend every identity (`external-tester-revoke.sql` or Admin Members), delete the admin role row,
expire any unused invitation, remove the Play tester entry if he is not continuing, and rotate any
password account in the Auth dashboard.
