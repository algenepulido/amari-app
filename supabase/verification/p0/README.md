# P0 invitation containment, verification apparatus

These four files reproduce the verification that was run before the P0 invitation containment was
applied to production on 2026-09-22T01:15:06Z. They are not CI tests and must not live under
`supabase/tests/`.

## Why they are here and not there

`supabase test db` runs pg_prove over everything beneath `supabase/tests/`, including any
subdirectory. While these sat there, CI ran the fixtures as if they were TAP tests and reported
three failures for "No plan found in TAP output" purely because of where the files were, and ran
the containment test against a bare migrated database it was never written for.

They need a database shaped like production: members, administrators, the legacy invitation pool
and PostGIS. CI builds an empty database from migrations and seeds nothing, so 12 of the 45
planned assertions cannot run there and test 18 fails outright on `permission denied for table
members`, which is the guard working rather than a defect.

## What each file is

`p0-production-faithful-fixture.sql` builds the production-shaped database: the schema, the member
and administrator rows, and the legacy invitation pool including the weak and predictable codes.
Fidelity against the real thing is recorded in `docs/P0_FIXTURE_FIDELITY_MANIFEST.md`: 43 objects
compared, 43 matching, 0 divergent.

`p0_invitation_containment.test.sql` is the pgTAP suite, 45 planned assertions covering the
expiry of the weak pool, the reissue, redemption binding to `auth.uid()`, the grant revocations
and the tier enforcement on the map functions.

`p0-authorisation-matrix.sql` probes every role against every affected function and records what
each one is permitted. Errors in its output are the expected result, not failures: `permission
denied for function map_projects` and `membership required` are the guards refusing, which is the
point of the matrix. Results are in `docs/EXTERNAL_REVIEWER_AUTHORISATION_MATRIX.md`.

`schema-signature.sql` captures the schema signature used to compare the fixture against
production.

## How to run them

Against a disposable Postgres with PostGIS, never against production and never against the linked
project.

```
docker run --rm -d --name p0-verify -e POSTGRES_PASSWORD=postgres -p 55432:5432 postgis/postgis:17-3.5
psql "postgresql://postgres:postgres@localhost:55432/postgres" -v ON_ERROR_STOP=1 \
     -f supabase/verification/p0/p0-production-faithful-fixture.sql
psql "postgresql://postgres:postgres@localhost:55432/postgres" -v ON_ERROR_STOP=1 \
     -f supabase/migrations/20260921000001_p0_invitation_containment.sql
pg_prove -d "postgresql://postgres:postgres@localhost:55432/postgres" \
     supabase/verification/p0/p0_invitation_containment.test.sql
docker rm -f p0-verify
```

The containment migration itself is replayable on an empty database as of 24 September 2026. Its
map smoke test skips when no administrator exists, and the sibling short-codes migration asserts
that membership is unchanged rather than that it equals the production count. Both amendments are
recorded in `docs/SECURITY-P0-CONTAINMENT-2026-09-22.md`, along with the hashes that actually ran
against production.
