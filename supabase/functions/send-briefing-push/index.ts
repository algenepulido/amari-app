// @ts-nocheck
// Briefing push: "Your briefing is ready." Runs on a daily cron but
// self-regulates — sends at most once every 3 days, and only when enough
// fresh coverage has been published since the last send. One tasteful
// push, never spam. Tap routes to /briefing in the app.
//
// Auth: x-amari-pipeline-secret header or admin JWT (same as the pipeline).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PIPELINE_SECRET = Deno.env.get('NEWS_PIPELINE_SECRET') ?? '';

const MIN_DAYS_BETWEEN_SENDS = 3;
const MIN_FRESH_ARTICLES = 8; // don't announce a briefing that isn't fresh
const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send';
const CHUNK = 90;

function jsonResponse(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function isAuthorized(req: Request): Promise<boolean> {
  const secret = req.headers.get('x-amari-pipeline-secret');
  if (PIPELINE_SECRET && secret === PIPELINE_SECRET) return true;

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return false;
  const accessToken = authHeader.slice(7).trim();
  if (!accessToken) return false;

  const memberClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
  const { data: { user }, error } = await memberClient.auth.getUser(accessToken);
  if (error || !user) return false;
  const { data: isAdmin } = await memberClient.rpc('is_admin');
  return Boolean(isAdmin);
}

Deno.serve(async (req: Request) => {
  try {
    if (!(await isAuthorized(req))) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Cadence gate: at most one briefing push per 3 days.
    const { data: lastPush } = await serviceClient
      .from('push_log')
      .select('sent_at')
      .eq('kind', 'briefing')
      .order('sent_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (lastPush) {
      const ageMs = Date.now() - new Date(lastPush.sent_at).getTime();
      if (ageMs < MIN_DAYS_BETWEEN_SENDS * 24 * 3600 * 1000) {
        return jsonResponse({ success: true, skipped: 'cadence', last_sent: lastPush.sent_at });
      }
    }

    // Freshness gate: only announce a briefing with genuinely new coverage.
    const sinceIso = lastPush
      ? lastPush.sent_at
      : new Date(Date.now() - MIN_DAYS_BETWEEN_SENDS * 24 * 3600 * 1000).toISOString();
    const { count: freshCount } = await serviceClient
      .from('news_articles')
      .select('id', { count: 'exact', head: true })
      .eq('status', 'published')
      .gte('ingested_at', sinceIso);

    if ((freshCount ?? 0) < MIN_FRESH_ARTICLES) {
      return jsonResponse({ success: true, skipped: 'not_enough_fresh_content', fresh: freshCount ?? 0 });
    }

    // Recipients: active members with a token who haven't disabled pulse pushes.
    const { data: members, error: memberError } = await serviceClient
      .from('members')
      .select('id, expo_push_token, notification_preferences')
      .eq('status', 'active')
      .not('expo_push_token', 'is', null);

    if (memberError) throw memberError;

    const recipients = (members ?? []).filter((m) => {
      const prefs = m.notification_preferences as { pulse?: boolean } | null;
      return prefs?.pulse !== false && typeof m.expo_push_token === 'string' && m.expo_push_token.startsWith('ExponentPushToken');
    });

    if (!recipients.length) {
      return jsonResponse({ success: true, skipped: 'no_recipients', fresh: freshCount });
    }

    const messages = recipients.map((m) => ({
      to: m.expo_push_token,
      title: 'Your briefing is ready',
      body: `${freshCount} new stories on the people, markets, and ideas you follow.`,
      data: { type: 'briefing' },
      sound: null,
    }));

    let sent = 0;
    for (let i = 0; i < messages.length; i += CHUNK) {
      const chunk = messages.slice(i, i + CHUNK);
      const response = await fetch(EXPO_PUSH_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(chunk),
      });
      if (response.ok) sent += chunk.length;
      else console.error('[briefing-push] chunk failed:', response.status, (await response.text()).slice(0, 200));
    }

    await serviceClient.from('push_log').insert({
      kind: 'briefing',
      recipients: sent,
      meta: { fresh_articles: freshCount },
    });

    return jsonResponse({ success: true, sent, fresh: freshCount });
  } catch (error) {
    console.error('[briefing-push] Error:', error);
    return jsonResponse(
      { error: 'Push failed', details: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
