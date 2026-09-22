-- ============================================================================
-- Short, human-usable invitation codes, plus the throttle that makes them safe
--
-- Two changes that only work as a pair.
--
-- The 48 character codes introduced during P0 containment are secure and
-- unusable. Nobody should be asked to read one over the phone or type one on a
-- handset, and the transcription risk is real.
--
-- Six characters from a 32 symbol alphabet is 30 bits, about 1.07 billion
-- combinations. That is only safe because validate_invitation_code stops
-- answering an unlimited number of anonymous questions. Shortening the code
-- without the throttle would put us back where we were before containment, so
-- the two are deliberately in one migration and must not be separated.
--
-- Alphabet is Crockford base32: digits and letters with I, L, O and U removed.
-- That removes the 1 against I and 0 against O confusion that generates support
-- tickets, leaves 32 symbols so a random byte modulo 32 is unbiased, and is
-- already upper case, which matters because the server upper cases before
-- hashing.
--
-- Also expires invitation 2068, which was created for the finalist reviewer but
-- was misaddressed and whose code was exposed in a chat transcript.
--
-- One transaction. Nothing deleted. No grant, policy or table altered.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Generator: six Crockford base32 characters
-- ---------------------------------------------------------------------------
create or replace function public.generate_share_invite_code(p_prefix text default 'AMARI-INV')
returns text
language plpgsql
security definer
set search_path = public, extensions
as $gen$
declare
  -- Crockford base32. I, L, O and U are deliberately absent.
  c_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  c_length   constant integer := 6;
  v_candidate text;
  v_suffix    text;
  v_bytes     bytea;
  i           integer;
begin
  loop
    v_suffix := '';
    v_bytes := extensions.gen_random_bytes(c_length);

    -- 256 divides evenly by 32, so modulo introduces no bias.
    for i in 0 .. c_length - 1 loop
      v_suffix := v_suffix || substr(c_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;

    v_candidate := upper(coalesce(p_prefix, 'AMARI-INV')) || '-' || v_suffix;

    exit when not exists (
      select 1 from public.invitation_codes where code = v_candidate
    );
  end loop;

  return v_candidate;
end;
$gen$;

revoke execute on function public.generate_share_invite_code(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Throttle on validation
--
--    Two limits. A per caller limit keyed on the authenticated subject where
--    there is one, and otherwise on the forwarded address, which is only a best
--    effort because a caller can influence it. The global limit is the backstop
--    that a spoofing attacker cannot evade.
--
--    Real usage is tiny: 23 members and three joins in the last 90 days. A
--    global ceiling of 120 a minute is far above anything legitimate and far
--    below what a brute force needs.
--
--    The response shape is unchanged, and the shipped client already handles
--    the rate_limited error at app/(auth)/invite.tsx:60 and
--    components/v2/Onboarding.tsx:324.
-- ---------------------------------------------------------------------------
create index if not exists rate_limits_endpoint_created_idx
  on public.rate_limits (endpoint, created_at desc);

create or replace function public.validate_invitation_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  c_per_caller_max    constant integer := 10;
  c_per_caller_window constant interval := interval '10 minutes';
  c_global_max        constant integer := 120;
  c_global_window     constant interval := interval '1 minute';

  v_hash    text;
  v_exists  boolean;
  v_key     text;
  v_count   integer;
begin
  if p_code is null or btrim(p_code) = '' then
    return jsonb_build_object('valid', false);
  end if;

  -- Identify the caller as well as we can. auth.uid() is trustworthy. The
  -- forwarded address is not, which is why the global ceiling exists.
  v_key := coalesce(
    auth.uid()::text,
    nullif(btrim(split_part(
      coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''),
      ',', 1)), ''),
    'unknown'
  );

  -- Global ceiling first. A caller spoofing addresses still meets this.
  select count(*) into v_count
    from public.rate_limits
   where endpoint = 'invite_validate_global'
     and created_at > now() - c_global_window;

  if v_count >= c_global_max then
    return jsonb_build_object('valid', false, 'error', 'rate_limited');
  end if;

  -- Then the per caller limit.
  select count(*) into v_count
    from public.rate_limits
   where endpoint = 'invite_validate'
     and ip_address = v_key
     and created_at > now() - c_per_caller_window;

  if v_count >= c_per_caller_max then
    return jsonb_build_object('valid', false, 'error', 'rate_limited');
  end if;

  insert into public.rate_limits (ip_address, endpoint) values (v_key, 'invite_validate');
  insert into public.rate_limits (ip_address, endpoint) values (v_key, 'invite_validate_global');

  -- Keep the table small without depending on a scheduled job. Cheap, and only
  -- runs on roughly one call in fifty.
  if random() < 0.02 then
    delete from public.rate_limits where created_at < now() - interval '2 hours';
  end if;

  v_hash := encode(extensions.digest(upper(btrim(p_code)), 'sha256'), 'hex');

  select exists (
    select 1
    from public.invitation_codes
    where code_hash = v_hash
      and used_by is null
      and expires_at > now()
  ) into v_exists;

  return jsonb_build_object('valid', v_exists);
end;
$fn$;

revoke execute on function public.validate_invitation_code(text) from public;
grant execute on function public.validate_invitation_code(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Expire the burned finalist invitation
--
--    Row 2068 was created for the finalist reviewer, was addressed to a
--    mistyped address, and its code was pasted into a chat transcript. Expired
--    rather than deleted, so the audit trail survives.
-- ---------------------------------------------------------------------------
update public.invitation_codes
   set expires_at = now()
 where id = 2068
   and used_by is null;

-- ---------------------------------------------------------------------------
-- 4. Assertions. Commit only if all of them hold.
-- ---------------------------------------------------------------------------
do $assert$
declare
  v_sample      text;
  v_suffix_len  integer;
  v_bad_chars   integer;
  v_burned_live integer;
  v_members     integer;
  v_admins      integer;
begin
  -- The generator must produce the new shape.
  v_sample := public.generate_share_invite_code('AMARI-TEST');
  v_suffix_len := length(v_sample) - length('AMARI-TEST') - 1;
  if v_suffix_len <> 6 then
    raise exception 'generator produced a % character suffix, expected 6', v_suffix_len;
  end if;

  -- And only from the Crockford alphabet.
  v_bad_chars := length(regexp_replace(
    substr(v_sample, length('AMARI-TEST') + 2),
    '[0-9ABCDEFGHJKMNPQRSTVWXYZ]', '', 'g'));
  if v_bad_chars <> 0 then
    raise exception 'generator produced % character(s) outside the Crockford alphabet', v_bad_chars;
  end if;

  -- The burned invitation must no longer be usable.
  select count(*) into v_burned_live
    from public.invitation_codes
   where id = 2068 and used_by is null and expires_at > now();
  if v_burned_live <> 0 then
    raise exception 'invitation 2068 is still valid and unused';
  end if;

  -- Nothing about membership may move.
  select count(*) into v_members from public.members;
  select count(*) into v_admins  from public.admin_roles;
  if v_members <> 23 then
    raise exception 'member count changed to %, expected 23', v_members;
  end if;
  if v_admins <> 4 then
    raise exception 'administrator count changed to %, expected 4', v_admins;
  end if;

  raise notice 'short codes live: 6 Crockford characters, validation throttled at % per caller per 10 min and % globally per minute, invitation 2068 expired',
    10, 120;
end;
$assert$;

commit;
