-- Verification for batch 1 (HO-07, HO-25, HO-03). Run as a privileged role against a
-- build that has the migration applied. Each block impersonates a real user with
-- request.jwt.claims and rolls back. Expected results are in the RAISE lines.
-- HO-07: a suspended admin must fail is_admin().
do $$ declare v boolean; begin
  perform set_config('request.jwt.claims','{"sub":"<SUSPENDED_ADMIN_UUID>","role":"authenticated"}', true);
  v := public.is_admin();
  raise notice 'HO-07 suspended admin is_admin() = % (expect f)', v;
end $$;
-- HO-03: a non-admin changing a project status must raise.
-- HO-25: a first RSVP to a capacity event must insert exactly one row and report success.
-- (See work/fixes/batch1-note.md for the full seeded reproduction used in testing.)
