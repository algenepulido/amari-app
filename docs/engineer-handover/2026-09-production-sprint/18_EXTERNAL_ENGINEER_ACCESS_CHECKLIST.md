# External engineer access checklist

For Jeremy. Status values: DONE, TO INVITE, TO CREATE, TO CONFIRM, NOT NEEDED YET. Grant the least
role listed. Never send a password, a service-role key or a signing credential.

| Item | Status | Least privilege | Notes |
|---|---|---|---|
| [ ] GitHub collaborator, `algenepulido` | TO INVITE | Write on `amari-app`; protect `release/v2-redesign-signed` with required PR review | Not Admin |
| [ ] Supabase project access | TO INVITE | Read-only or developer role on the production project | No database password or service-role key |
| [ ] Safe test or staging environment | TO CONFIRM | Local Docker from the repository (free), or a staging project you approve | See `04` |
| [ ] Active-member test identity (silver) | TO CREATE | Invitation at silver | Prefer staging |
| [ ] Lower-tier identity (member) | TO CREATE | Invitation at member | |
| [ ] Higher-tier identity (gold or platinum) | TO CREATE | Invitation at gold, raise if needed | On production this shows real members' data: decide deliberately |
| [ ] Admin identity | TO CREATE | `admin_roles` row, owner-inserted, with an end date | No tooling exists; staging strongly preferred |
| [ ] Suspended identity | TO CREATE | Active member, then suspend | Never suspend a real member |
| [ ] Media-publishing admin | NOT NEEDED YET | Reuse admin | No media workflow exists yet |
| [ ] Two fresh invitation codes | TO CREATE | Member or silver, six-character format | Deliver separately from the account email; never in chat |
| [ ] Android closed-test access, `algene.pulido@gmail.com` | TO INVITE | Add to an Alpha tester list, send the opt-in link | He must accept; counts towards the 12 |
| [ ] Expo / EAS access | TO CONFIRM | Developer role in an Expo organisation | Personal accounts cannot add members |
| [ ] Apple App Store Connect | TO CONFIRM | TestFlight tester; App Manager only if he submits | Individual accounts cannot add team members |
| [ ] Google Play Console release access | NOT NEEDED YET | Release permissions for this app only | Only when he runs a release |
| [ ] Sentry or equivalent | TO CONFIRM | Member of an AMARI-owned project | Needs your approval if paid |
| [ ] Mapbox | TO CONFIRM | His own scoped download token | Only for local native builds |
| [ ] Google Cloud OAuth clients | TO CONFIRM | Viewer | For Google Sign-In work |
| [ ] Website `/auth-callback` source | TO CONFIRM | Read access | For deep-link work |
| [ ] Readiness report PDF (5 Sep) | TO INVITE | Send privately | It contains live security detail |
| [ ] Play developer verification due 30 Sep 2026 | TO CONFIRM | Owner task | From Play Console notice |
