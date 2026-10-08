// @ts-nocheck
// AMARI map cache refresh
// This edge function is admin-triggered only. The actual cache rebuild happens in
// the database via the locked-down refresh_map_cache() function.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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

    const memberClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      },
    });

    const {
      data: { user },
      error: userError,
    } = await memberClient.auth.getUser(accessToken);

    if (userError || !user) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    const { data: isAdmin, error: adminError } = await memberClient.rpc('is_admin');

    if (adminError) {
      throw adminError;
    }

    if (!isAdmin) {
      return jsonResponse({ error: 'Forbidden' }, 403);
    }

    const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    const { error: refreshError } = await serviceClient.rpc('refresh_map_cache');
    if (refreshError) {
      throw refreshError;
    }

    const [
      { count: countries, error: countriesError },
      { count: states, error: statesError },
      { count: projects, error: projectsError },
    ] = await Promise.all([
      serviceClient.from('map_cache_countries').select('id', { count: 'exact', head: true }),
      serviceClient.from('map_cache_states').select('id', { count: 'exact', head: true }),
      serviceClient.from('map_cache_projects').select('id', { count: 'exact', head: true }),
    ]);

    if (countriesError || statesError || projectsError) {
      throw countriesError ?? statesError ?? projectsError;
    }

    return jsonResponse({
      success: true,
      message: 'Map cache refreshed',
      counts: {
        countries: countries ?? 0,
        states: states ?? 0,
        projects: projects ?? 0,
      },
      refreshed_by: user.id,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('[map-refresh] Error:', error);
    return jsonResponse(
      {
        error: 'Refresh failed',
        details: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});
