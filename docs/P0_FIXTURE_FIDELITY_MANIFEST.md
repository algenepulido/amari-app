# P0 fixture fidelity manifest

Generated 22 September 2026 by comparing a read-only production metadata capture
against the rebuilt disposable fixture. Production was not modified to produce this.

The production side is the state **before** the containment migration, which is the
correct baseline for a fixture that then applies it.

## Why this exists

Two earlier fixtures passed while production could not run the same migration. The first
declared `invitation_codes.id` as `uuid` where production has `bigint`, which aborted the
first production attempt. The second omitted the `members` display identifier trigger
entirely, which would have broken every redemption test for a different reason. A fixture
that diverges from production does not test the thing being deployed.

## Result

Objects compared: **43**. Matching: **43**. Divergent: **0**.

| Object | Production | Fixture | Match |
|---|---|---|---|
| Column `admin_roles.created_at` | timestamp with time zone / timestamptz / nullable=YES | timestamp with time zone / timestamptz / nullable=YES | yes |
| Column `admin_roles.member_id` | uuid / uuid / nullable=NO | uuid / uuid / nullable=NO | yes |
| Column `admin_roles.role` | text / text / nullable=NO | text / text / nullable=NO | yes |
| Column `invitation_codes.code` | text / text / nullable=NO | text / text / nullable=NO | yes |
| Column `invitation_codes.code_hash` | text / text / nullable=YES | text / text / nullable=YES | yes |
| Column `invitation_codes.code_prefix` | text / text / nullable=YES | text / text / nullable=YES | yes |
| Column `invitation_codes.created_at` | timestamp with time zone / timestamptz / nullable=YES | timestamp with time zone / timestamptz / nullable=YES | yes |
| Column `invitation_codes.expires_at` | timestamp with time zone / timestamptz / nullable=NO | timestamp with time zone / timestamptz / nullable=NO | yes |
| Column `invitation_codes.grants_admin` | boolean / bool / nullable=NO | boolean / bool / nullable=NO | yes |
| Column `invitation_codes.id` | bigint / int8 / nullable=NO | bigint / int8 / nullable=NO | yes |
| Column `invitation_codes.invite_source` | text / text / nullable=NO | text / text / nullable=NO | yes |
| Column `invitation_codes.issued_at` | timestamp with time zone / timestamptz / nullable=YES | timestamp with time zone / timestamptz / nullable=YES | yes |
| Column `invitation_codes.issued_by` | uuid / uuid / nullable=YES | uuid / uuid / nullable=YES | yes |
| Column `invitation_codes.recipient_email` | text / text / nullable=YES | text / text / nullable=YES | yes |
| Column `invitation_codes.recipient_name` | text / text / nullable=YES | text / text / nullable=YES | yes |
| Column `invitation_codes.staff_role_grant` | text / text / nullable=YES | text / text / nullable=YES | yes |
| Column `invitation_codes.tier_grant` | USER-DEFINED / membership_tier / nullable=YES | USER-DEFINED / membership_tier / nullable=YES | yes |
| Column `invitation_codes.used_at` | timestamp with time zone / timestamptz / nullable=YES | timestamp with time zone / timestamptz / nullable=YES | yes |
| Column `invitation_codes.used_by` | uuid / uuid / nullable=YES | uuid / uuid / nullable=YES | yes |
| Column `members.city` | text / text / nullable=YES | text / text / nullable=YES | yes |
| Column `members.created_at` | timestamp with time zone / timestamptz / nullable=YES | timestamp with time zone / timestamptz / nullable=YES | yes |
| Column `members.email` | text / text / nullable=NO | text / text / nullable=NO | yes |
| Column `members.full_name` | text / text / nullable=NO | text / text / nullable=NO | yes |
| Column `members.id` | uuid / uuid / nullable=NO | uuid / uuid / nullable=NO | yes |
| Column `members.industry` | text / text / nullable=YES | text / text / nullable=YES | yes |
| Column `members.status` | USER-DEFINED / member_status / nullable=NO | USER-DEFINED / member_status / nullable=NO | yes |
| Column `members.tier` | USER-DEFINED / membership_tier / nullable=NO | USER-DEFINED / membership_tier / nullable=NO | yes |
| Column `rate_limits.created_at` | timestamp with time zone / timestamptz / nullable=YES | timestamp with time zone / timestamptz / nullable=YES | yes |
| Column `rate_limits.endpoint` | text / text / nullable=NO | text / text / nullable=NO | yes |
| Column `rate_limits.id` | bigint / int8 / nullable=NO | bigint / int8 / nullable=NO | yes |
| Enum `member_status` | pending,active,suspended,inactive | pending,active,suspended,inactive | yes |
| Enum `membership_tier` | member,silver,gold,platinum,laureate | member,silver,gold,platinum,laureate | yes |
| Function `check_rate_limit(p_ip text, p_endpoint text, p_max_requests integer, p_window_minutes integer)` | returns boolean / secdef=true / lang=plpgsql | returns boolean / secdef=true / lang=plpgsql | yes |
| Function `cleanup_rate_limits()` | returns void / secdef=false / lang=sql | returns void / secdef=false / lang=sql | yes |
| Function `generate_share_invite_code(p_prefix text)` | returns text / secdef=true / lang=plpgsql | returns text / secdef=true / lang=plpgsql | yes |
| Function `get_member_tier()` | returns membership_tier / secdef=true / lang=plpgsql | returns membership_tier / secdef=true / lang=plpgsql | yes |
| Function `is_active_member()` | returns boolean / secdef=true / lang=sql | returns boolean / secdef=true / lang=sql | yes |
| Function `is_admin()` | returns boolean / secdef=true / lang=sql | returns boolean / secdef=true / lang=sql | yes |
| Function `map_countries(category_filter text)` | returns TABLE(country_code text, country_name text, project_count integer, categories jsonb, lat double pre... | returns TABLE(country_code text, country_name text, project_count integer, categories jsonb, lat double pre... | yes |
| Function `map_projects(min_lat double precision, min_lng double precision, max_lat double precision, max_lng double precision, category_filter text)` | returns TABLE(project_id uuid, name text, description text, category text, creator_first_name text, display... | returns TABLE(project_id uuid, name text, description text, category text, creator_first_name text, display... | yes |
| Function `map_states(min_lat double precision, min_lng double precision, max_lat double precision, max_lng double precision, category_filter text)` | returns TABLE(state_province text, display_label text, project_count integer, categories jsonb, lat double ... | returns TABLE(state_province text, display_label text, project_count integer, categories jsonb, lat double ... | yes |
| Function `redeem_invitation_code(p_code text, p_user_id uuid, p_full_name text, p_email text, p_city text, p_industry text)` | returns jsonb / secdef=true / lang=plpgsql | returns jsonb / secdef=true / lang=plpgsql | yes |
| Function `validate_invitation_code(p_code text)` | returns jsonb / secdef=true / lang=plpgsql | returns jsonb / secdef=true / lang=plpgsql | yes |

## Present in the fixture but not in production

None.

## Known and accepted divergences

**PostGIS is substituted.** The host does not have the free memory to run a PostGIS
container alongside the other work on this machine; two attempts were killed for memory
with 0.69 GB free of 15.69 GB. The `geometry` type and the five spatial functions used by
the map queries are stand-ins placed in the `extensions` schema, so the migration's fixed
`search_path` of `public, extensions` is still genuinely exercised. This affects spatial
evaluation only. It does not affect the grants, the tier gating or the invitation
lifecycle, which are what the migration changes. The one risk it cannot cover, that
PostGIS lives in a schema outside the fixed path in production, is covered instead by the
smoke test inside the migration, which aborts the whole transaction if the map functions
cannot run.

**`generate_display_id` is simplified.** Production generates a member display identifier
with its own algorithm. The fixture generates a random one of the same shape. The value is
never asserted on; what matters is that the trigger fires and satisfies the `NOT NULL`
constraint, which is what production does.

**Only the objects in scope are reproduced.** Production has 47 tables and several hundred
functions. The fixture reproduces the tables, types, triggers and functions the migration
and its tests touch, which are the ones listed above.
