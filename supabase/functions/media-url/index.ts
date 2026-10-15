// @ts-nocheck
// Media playback URL. The member's app calls this with their session. It asks the
// database (request_media_playback) whether this member may play the item, and only
// on an "allowed" result does it mint a short-lived signed URL for the file with the
// service role. The signed URL is the only way a member ever reaches a media file:
// the private "media" bucket has no member read policy, and storage_path is never
// returned to a member who is not entitled to play.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const SIGNED_URL_TTL_SECONDS = 300;

// Map the database's refusal reasons onto HTTP status codes.
const ERROR_STATUS: Record<string, number> = {
  not_authenticated: 401,
  not_member: 403,
  tier_too_low: 403,
  not_found: 404,
};

function jsonResponse(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }
    const accessToken = authHeader.slice(7).trim();
    if (!accessToken) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    let body: { media_id?: string };
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: 'invalid_body' }, 400);
    }
    const mediaId = body?.media_id;
    if (!mediaId || typeof mediaId !== 'string') {
      return jsonResponse({ error: 'media_id_required' }, 400);
    }

    // Ask the database, as this member, whether playback is allowed. The RPC runs the
    // membership, publish and tier checks; it returns the storage path only on allow.
    const memberClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    });
    const { data: decision, error: rpcError } = await memberClient.rpc('request_media_playback', {
      p_media_id: mediaId,
    });
    if (rpcError) {
      return jsonResponse({ error: 'playback_check_failed', details: rpcError.message }, 500);
    }

    if (!decision?.allowed) {
      const reason = (decision?.error as string) ?? 'forbidden';
      return jsonResponse(
        { error: reason, required_tier: decision?.required_tier ?? null },
        ERROR_STATUS[reason] ?? 403,
      );
    }

    // Allowed: mint a short-lived signed URL for the file with the service role, which
    // bypasses the bucket's admin-only policies. The member never sees the raw path.
    const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: signed, error: signError } = await serviceClient
      .storage.from('media')
      .createSignedUrl(decision.storage_path as string, SIGNED_URL_TTL_SECONDS);

    if (signError || !signed?.signedUrl) {
      return jsonResponse({ error: 'could_not_sign_url', details: signError?.message }, 500);
    }

    return jsonResponse({
      url: signed.signedUrl,
      expires_in: SIGNED_URL_TTL_SECONDS,
      media_type: decision.media_type,
      title: decision.title,
      duration_seconds: decision.duration_seconds ?? null,
    });
  } catch (error) {
    console.error('[media-url] Error:', error);
    return jsonResponse(
      { error: 'media_url_failed', details: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
