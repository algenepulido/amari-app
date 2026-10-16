#!/usr/bin/env bash
#
# HO-04 concurrency check for the invitation redeem throttle.
#
# redeem_invitation_code counts the rate_limits rows for the caller and then inserts a new one.
# Without a lock, enough requests arriving together all read the count below the per-caller cap
# and all pass, so more than the cap get through. 20261008000002 wraps that count-then-insert in
# a transaction-scoped advisory lock (pg_advisory_xact_lock), which serializes it so no more than
# the cap ever pass.
#
# This script fires N concurrent redeems from one caller against a code that does not exist, so
# nothing is actually redeemed and the only thing being measured is how many requests get past
# the throttle before it starts returning rate_limited. The per-caller cap is 10.
#
# Run it against a local database that has the migration applied:
#   supabase db reset
#   bash scripts/concurrency/redeem-throttle-concurrency.sh
#
# Expected with the lock in place: 10 pass, the rest are rate_limited, and the script prints PASS.
# To see the race the lock prevents, apply the rollback and rerun:
#   psql "$DB" -f scripts/rollback-20261008000002_ho04_atomic_throttle.sql
#   bash scripts/concurrency/redeem-throttle-concurrency.sh      # now more than 10 pass: FAIL
#   psql "$DB" -f supabase/migrations/20261008000002_ho04_atomic_throttle.sql   # restore
#
# Optional arguments: DB_URL (default local) and N concurrent requests (default 25). The N
# argument is also how to rerun this at an expected launch-event load once that number is known.

set -uo pipefail

DB="${1:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
N="${2:-25}"
CAP=10
CALLER='bbbb0000-0000-0000-0000-0000000000cc'

# A caller with an auth row and no membership, and a clean throttle window.
psql "$DB" -q <<SQL
insert into auth.users (id, aud, role, email, instance_id, created_at, updated_at)
values ('$CALLER','authenticated','authenticated','concurrency@pgtap.invalid','00000000-0000-0000-0000-000000000000', now(), now())
on conflict (id) do nothing;
delete from public.rate_limits where ip_address = '$CALLER';
SQL

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for i in $(seq 1 "$N"); do
  psql "$DB" -tAc "select set_config('request.jwt.claims','{\"sub\":\"$CALLER\",\"role\":\"authenticated\"}', false); select coalesce(public.redeem_invitation_code('NOSUCHCODE','$CALLER','N','concurrency@pgtap.invalid') ->> 'error', 'passed');" > "$TMP/$i.out" 2>&1 &
done
wait

LIMITED="$(grep -l 'rate_limited' "$TMP"/*.out 2>/dev/null | wc -l | tr -d ' ')"
PASSED=$(( N - LIMITED ))

echo "concurrent requests: $N    passed throttle: $PASSED    rate_limited: $LIMITED    per-caller cap: $CAP"

if [ "$PASSED" -le "$CAP" ]; then
  echo "PASS: no more than the cap got through, so the throttle held under concurrency."
  exit 0
else
  echo "FAIL: $PASSED got through a cap of $CAP, so the count-then-insert raced."
  exit 1
fi
