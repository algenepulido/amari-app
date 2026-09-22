# External tester access runbook

How to give an external candidate temporary access to the live iOS app and the Android closed
test, track it, and take it away again.

Nothing here needs a new build. iOS is live on the App Store and Android is in closed testing, so
both platforms can be opened today.

## What a tester gets

An ordinary member account on production, at member tier unless you decide otherwise, created by
a 192-bit invitation addressed to them personally, with an expiry on the invitation and a tracked
record so access can be ended deliberately rather than from memory.

They cannot become an administrator. The Admin Codes screen and the issuing script both refuse to
create an admin or staff invitation outright.

At member tier they see Pulse, the briefing, events and their own profile. They cannot reach
Aligned or the project map, which is where other members' names, employers and project detail
live, because those now require gold tier or above and enforce it in the database.

## Prerequisites, once

The connection is already configured. `PGPASSFILE` points at the libpq password file and the four
non-secret variables are set. If a new machine needs setting up, use
`secure-output/setup-db-access.ps1`.

Before first use, apply `supabase/migrations/20260922000001_external_tester_access.sql`, which adds
the tracking table. It adds one table and alters nothing existing.

## Granting access

**Collect from the candidate.** Email address for the review, whether they can test iOS, Android or
both, device model and OS version, and for Android the Google account they use with Google Play.

**Android only, in Play Console.** Add their Google account to the closed testing track and send
them the opt-in link. This is the step that gates Android, and it is entirely outside the database.

**Fill the tester list.** Edit `secure-output/external-testers.csv`, which is gitignored:

```
tester_name,tester_email,platform,intended_tier
Ariful,ariful@example.com,both,member
```

`platform` is `ios`, `android` or `both`. `intended_tier` is normally `member`. The script refuses
`platinum` and `laureate` for an external tester unless you deliberately override it.

**Issue the invitations.**

```
psql -w -v ON_ERROR_STOP=1 -v access_days=14 \
     -f scripts/external-tester-issue.sql > secure-output/tester-codes.txt
```

The codes print once, into `secure-output`, which is gitignored. Send each candidate their own
code individually. Do not paste that file into chat or email it as a group.

The script refuses to issue a second live invitation to somebody who already has one, so it is safe
to re-run after adding a name to the list.

**Alternative for one-offs.** The Admin, Codes screen in the app does the same thing and now
generates 192-bit codes automatically. It does not create a tracking record, so prefer the script
when you want the revoke to be reliable later.

## Shared reviewer account, when the tester cannot give you an email

Use this when a candidate is under an Upwork trial and should not be handing over a personal
email address before a contract is agreed. It is iOS only, and on iOS it needs nothing from
them at all, because the app is public on the App Store.

The app already supports it. `app/(auth)/invite.tsx` ships three sign-in modes and the third is
reached by tapping **Reviewer password access**. It calls `signInWithPassword` with an email and
password rather than an invitation code, it is rendered unconditionally, and it is in the live
1.2.5 build. No code change and no new build are required.

**Do not reuse the Apple App Review demo account** recorded under "App Review Access" in
`docs/RELEASE-WORKFLOW.md`. If a tester changes its password or its state, the next App Store
review breaks. Each reviewer gets their own account.

**Create the auth user yourself** in the Supabase dashboard, Authentication, Users, Add user,
with **Auto Confirm User** ticked, and set the password there. Auto-confirm means the mailbox
never has to receive anything, so an address like `reviewer1@amarigala.com` works even if no
mail is routed to it. Doing it this way keeps the password out of every transcript, command
line and log.

**Then provision the member side:**

```
psql -w -v ON_ERROR_STOP=1 -v email=reviewer1@amarigala.com -v tier=silver -v days=14      -f scripts/reviewer-account-provision.sql
```

Dry run is the default. Add `-v dry_run=off` to apply. The script refuses any account holding an
admin role, refuses platinum and laureate outright, writes a tracking row, and asserts the result
before committing.

**Tier.** `tier_level` is member 1, silver 2, gold 3. Pulse summary content needs 2 and full
content needs 3. Aligned and the project map need gold and enforce it in the database. Silver is
the working default: it gives a materially fuller review than member tier while still exposing no
real member names, employers or project detail. Gold exposes all three for 23 real people.

**The tester's path, once you send them the credentials:** install AMARI from the App Store, swipe
through onboarding to the invitation step, tap **Already a member? Sign in**, then tap **Reviewer
password access**, enter the email and password, and Sign In.

**Revoking.** `scripts/external-tester-revoke.sql` as below, and rotate the password in the
Supabase dashboard at the same time, because a shared credential may have been passed on.

## Telling the candidate what to do

For iOS: install AMARI from the App Store, open it, choose to enter an invitation code, paste the
code you sent, then sign in with Apple, Google or email.

For Android: accept the closed testing invitation using the Google account you added, install from
the link, then the same invitation and sign-in flow.

Worth saying explicitly in your message: at member tier some areas will not be reachable, and that
is expected rather than a fault. A candidate who reports what they could not reach and what they
would verify is giving you a better signal than one who describes screens they could not have seen.

## Revoking access

Always dry run first. Dry run is the default, so you have to opt in to changing anything.

```
psql -w -v ON_ERROR_STOP=1 -v who=all -f scripts/external-tester-revoke.sql
```

Then apply:

```
psql -w -v ON_ERROR_STOP=1 -v who=all -v dry_run=off -f scripts/external-tester-revoke.sql
```

One tester instead of all:

```
psql -w -v ON_ERROR_STOP=1 -v who=ariful@example.com -v dry_run=off -f scripts/external-tester-revoke.sql
```

It expires any invitation they never used, suspends the account of anyone who did redeem, and
stamps the tracking record. It deletes nothing, so the history survives.

**Suspension is the real control.** Every member-reachable function checks `is_active_member()`, so
a suspended tester is refused by the database rather than merely hidden by the app. This was tested:
a tester goes from `is_active_member` true to false, and their unused invitations stop working.

The transaction verifies itself before committing. If any targeted tester is left unrevoked, or any
revoked tester still has an active account, it raises and the whole thing rolls back.

## Checking who currently has access

```sql
select tester_name, tester_email, platform, intended_tier,
       access_expires_at, revoked_at
from public.external_tester_access
order by granted_at desc;
```

That table is internal only: forced row level security with no policy, revoked from `public`,
`anon` and `authenticated`, granted only to `service_role`. Verified by attempting to read it as
both application roles and being denied.

## What to expect while testers are active

**Your administrators will get notifications.** Reporting an issue pushes to all four admins, and a
project contact request pushes to the real project owner. Warn them so it is not mistaken for
something going wrong.

**Tester activity lands in production analytics.** There is no cohort tagging, so engagement figures
for the trial period will include them. Worth remembering before reading any usage numbers from
these weeks.

**A redeemed invitation creates a permanent member until you revoke it.** There is no automatic
expiry on the account itself, only on the unredeemed invitation. That is exactly why the tracking
table and the revoke script exist.

## Limits worth knowing

There is no separate reviewer environment. Testers are on production, on the same Supabase project
as your 23 real members. The controls above are what stand between a tester and anything they should
not reach, and after the containment work of 22 September those controls are real and server-side.
The design for a fully isolated environment exists in `docs/EXTERNAL_REVIEWER_ACCESS_PLAN.md` if you
ever want it, and it needs a new Supabase project and a new build for both platforms.

Media V1 does not exist yet, so there is nothing for a tester to review there. Say so rather than
letting them look for it.
