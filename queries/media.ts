import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';

export type MediaType = 'audio' | 'video';

// Catalog rows every active member can see. The storage path is never included;
// a playable URL is fetched separately and only when the member is entitled.
export interface MediaCatalogItem {
  id: string;
  media_type: MediaType;
  title: string;
  description: string | null;
  artwork_path: string | null;
  duration_seconds: number | null;
  min_tier: string;
}

export interface MediaPlayback {
  url: string;
  expires_in: number;
  media_type: MediaType;
  title: string;
  duration_seconds: number | null;
}

export const mediaKeys = {
  all: ['media'] as const,
  catalog: () => [...mediaKeys.all, 'catalog'] as const,
};

export function useMediaCatalog() {
  return useQuery({
    queryKey: mediaKeys.catalog(),
    queryFn: async (): Promise<MediaCatalogItem[]> => {
      const { data, error } = await supabase.rpc('get_media_catalog');
      if (error) throw error;
      return (data ?? []) as MediaCatalogItem[];
    },
  });
}

// The server's refusal reasons, turned into one member-facing line each.
const PLAYBACK_MESSAGES: Record<string, string> = {
  tier_too_low: 'This is available from Gold membership.',
  not_found: 'This is no longer available.',
  not_member: 'Your membership is not active.',
  not_authenticated: 'Please sign in again.',
};

export class MediaPlaybackError extends Error {
  code: string;
  constructor(code: string) {
    super(PLAYBACK_MESSAGES[code] ?? 'This could not be played.');
    this.code = code;
  }
}

// Ask the media-url edge function for a short-lived signed URL. The function runs
// the membership, publish and tier checks server-side, so a refusal here is the
// authoritative gate, not anything the client decides.
export async function fetchMediaPlayback(mediaId: string): Promise<MediaPlayback> {
  const { data, error } = await supabase.functions.invoke('media-url', {
    body: { media_id: mediaId },
  });

  if (error) {
    let code = 'playback_failed';
    try {
      const ctx = (error as { context?: { json?: () => Promise<{ error?: string }> } }).context;
      if (ctx && typeof ctx.json === 'function') {
        const parsed = await ctx.json();
        if (parsed?.error) code = parsed.error;
      }
    } catch {
      // keep the generic code
    }
    throw new MediaPlaybackError(code);
  }

  if (!data?.url) {
    const reason = (data as { error?: string } | null)?.error ?? 'playback_failed';
    throw new MediaPlaybackError(reason);
  }

  return data as MediaPlayback;
}
