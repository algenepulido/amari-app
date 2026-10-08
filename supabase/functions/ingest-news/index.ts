// @ts-nocheck
// AMARI intelligence feed: bounded RSS ingestion.
// Stores feed-provided headline, snippet, image reference, and link only.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  buildEntityFeedUrl,
  ENTITIES_PER_RUN,
  ENTITY_ITEMS_PER_ENTITY,
  FETCH_CONCURRENCY,
  fetchAndParseFeed,
  GOOGLE_DISCOVERY_SOURCE_FEED_URL,
  mapWithConcurrency,
  sha256Hex,
  SOURCES_PER_RUN,
} from "./core.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PIPELINE_SECRET = Deno.env.get("NEWS_PIPELINE_SECRET") ?? "";
const LEASE_SECONDS = 180;

interface SourceRow {
  id: number;
  name: string;
  feed_url: string;
  region: string;
  fail_count: number | null;
  last_fetched_at: string | null;
}
interface EntityRow {
  id: number;
  name: string;
  aliases: string[] | null;
  region: string | null;
  last_checked_at: string | null;
}
interface SourceResult {
  source: string;
  source_id: number;
  status: string;
  items: number;
  inserted: number;
  empty: boolean;
  failed: boolean;
}
interface EntityResult {
  entity: string;
  entity_id: number;
  status: string;
  items: number;
  inserted: number;
  failed: boolean;
}

function jsonResponse(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
function elapsedMs(startedAt: number): number {
  return Math.round(performance.now() - startedAt);
}
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function isAuthorized(req: Request): Promise<boolean> {
  const secret = req.headers.get("x-amari-pipeline-secret");
  if (PIPELINE_SECRET && secret === PIPELINE_SECRET) return true;
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return false;
  const accessToken = authHeader.slice(7).trim();
  if (!accessToken) return false;
  const memberClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
  const { data: { user }, error: userError } = await memberClient.auth.getUser(
    accessToken,
  );
  if (userError || !user) return false;
  const { data: isAdmin } = await memberClient.rpc("is_admin");
  return Boolean(isAdmin);
}

async function processSource(
  serviceClient: ReturnType<typeof createClient>,
  source: SourceRow,
  discoverySourceId: number | null,
): Promise<SourceResult> {
  let inserted = 0;
  try {
    const items = await fetchAndParseFeed(source.feed_url);
    const isGoogleNews = source.feed_url.startsWith("https://news.google.com/");
    if (isGoogleNews && discoverySourceId === null) {
      throw new Error("Google News discovery source is not configured");
    }
    const rows = await Promise.all(items.map(async (item) => ({
      source_id: isGoogleNews ? discoverySourceId : source.id,
      url: item.url,
      url_hash: await sha256Hex(item.url),
      // Google News appends the actual publisher to the title; retain it because
      // the database source is deliberately the generic discovery service.
      title: item.title,
      snippet: item.snippet,
      image_url: item.imageUrl,
      published_at: item.publishedAt,
    })));
    if (rows.length > 0) {
      const { error: insertError, count } = await serviceClient.from(
        "news_articles",
      )
        .upsert(rows, {
          onConflict: "url_hash",
          ignoreDuplicates: true,
          count: "exact",
        });
      if (insertError) throw insertError;
      inserted = count ?? 0;
    }
    const now = new Date().toISOString();
    const { error: updateError } = await serviceClient.from("news_sources")
      .update({
        last_fetched_at: now,
        last_status: `ok: ${items.length} items, ${inserted} new`,
        fail_count: 0,
        updated_at: now,
      }).eq("id", source.id);
    if (updateError) throw updateError;
    return {
      source: source.name,
      source_id: source.id,
      status: "ok",
      items: items.length,
      inserted,
      empty: items.length === 0,
      failed: false,
    };
  } catch (error) {
    const status = errorMessage(error);
    const now = new Date().toISOString();
    await serviceClient.from("news_sources").update({
      last_fetched_at: now,
      last_status: `error: ${status}`,
      fail_count: (source.fail_count ?? 0) + 1,
      updated_at: now,
    }).eq("id", source.id);
    console.warn(`[ingest-news] source ${source.name}:`, status);
    return {
      source: source.name,
      source_id: source.id,
      status,
      items: 0,
      inserted,
      empty: false,
      failed: true,
    };
  }
}

async function processEntity(
  serviceClient: ReturnType<typeof createClient>,
  discoverySourceId: number,
  entity: EntityRow,
): Promise<EntityResult> {
  let inserted = 0;
  try {
    const feedUrl = buildEntityFeedUrl(entity.name, entity.aliases);
    const items = (await fetchAndParseFeed(feedUrl)).slice(
      0,
      ENTITY_ITEMS_PER_ENTITY,
    );
    const rows = await Promise.all(items.map(async (item) => ({
      source_id: discoverySourceId,
      url: item.url,
      url_hash: await sha256Hex(item.url),
      title: item.title,
      snippet: item.snippet,
      image_url: item.imageUrl,
      published_at: item.publishedAt,
      entities: [entity.name],
    })));
    if (rows.length > 0) {
      const { error: insertError, count } = await serviceClient.from(
        "news_articles",
      )
        .upsert(rows, {
          onConflict: "url_hash",
          ignoreDuplicates: true,
          count: "exact",
        });
      if (insertError) throw insertError;
      inserted = count ?? 0;
      for (const row of rows) {
        const { error: appendError } = await serviceClient.rpc(
          "append_article_entity",
          { p_url_hash: row.url_hash, p_entity: entity.name },
        );
        if (appendError) throw appendError;
      }
    }
    return {
      entity: entity.name,
      entity_id: entity.id,
      status: "ok",
      items: items.length,
      inserted,
      failed: false,
    };
  } catch (error) {
    const status = errorMessage(error);
    console.warn(`[ingest-news] entity ${entity.name}:`, status);
    return {
      entity: entity.name,
      entity_id: entity.id,
      status,
      items: 0,
      inserted,
      failed: true,
    };
  } finally {
    const { error: updateError } = await serviceClient.from("tracked_entities")
      .update({ last_checked_at: new Date().toISOString() }).eq(
        "id",
        entity.id,
      );
    if (updateError) {
      console.warn(
        `[ingest-news] entity rotation update ${entity.name}:`,
        updateError.message,
      );
    }
  }
}

Deno.serve(async (req: Request) => {
  const startedAt = performance.now();
  let serviceClient: ReturnType<typeof createClient> | null = null;
  let leaseToken: string | null = null;
  try {
    if (!(await isAuthorized(req))) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }
    serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: acquiredLease, error: leaseError } = await serviceClient.rpc(
      "try_acquire_news_pipeline_lease",
      {
        p_pipeline: "ingest-news",
        p_lease_seconds: LEASE_SECONDS,
      },
    );
    if (leaseError) throw leaseError;
    if (!acquiredLease) {
      return jsonResponse({
        success: true,
        already_running: true,
        elapsed_ms: elapsedMs(startedAt),
        sources_attempted: 0,
        entities_attempted: 0,
        timestamp: new Date().toISOString(),
      });
    }
    leaseToken = acquiredLease;

    const { data: discoverySource, error: discoverySourceError } =
      await serviceClient.from("news_sources")
        .select("id").eq("feed_url", GOOGLE_DISCOVERY_SOURCE_FEED_URL)
        .maybeSingle();
    if (discoverySourceError) throw discoverySourceError;

    const { data: sources, error: sourcesError } = await serviceClient.from(
      "news_sources",
    )
      .select("id, name, feed_url, region, fail_count, last_fetched_at").eq(
        "active",
        true,
      )
      .order("last_fetched_at", { ascending: true, nullsFirst: true }).order(
        "id",
        { ascending: true },
      ).limit(SOURCES_PER_RUN);
    if (sourcesError) throw sourcesError;
    const selectedSources = (sources ?? []) as SourceRow[];
    const sourceResults = await mapWithConcurrency(
      selectedSources,
      FETCH_CONCURRENCY,
      (source) => processSource(serviceClient!, source, discoverySource?.id ?? null),
    );

    const { data: renewedLease, error: renewError } = await serviceClient.rpc(
      "renew_news_pipeline_lease",
      {
        p_pipeline: "ingest-news",
        p_lease_id: leaseToken,
        p_lease_seconds: LEASE_SECONDS,
      },
    );
    if (renewError || renewedLease !== true) {
      throw new Error(renewError?.message ?? "Ingestion lease ownership lost");
    }

    const { data: entities, error: entitiesError } = await serviceClient.from(
      "tracked_entities",
    )
      .select("id, name, aliases, region, last_checked_at").eq("active", true)
      .eq("house", true).eq("status", "approved")
      .order("last_checked_at", { ascending: true, nullsFirst: true }).order(
        "id",
        { ascending: true },
      ).limit(ENTITIES_PER_RUN);
    if (entitiesError) throw entitiesError;
    const selectedEntities = (entities ?? []) as EntityRow[];
    const entityResults = discoverySource
      ? await mapWithConcurrency(
        selectedEntities,
        FETCH_CONCURRENCY,
        (entity) => processEntity(serviceClient!, discoverySource.id, entity),
      )
      : [];

    const sourceFailures = sourceResults.filter((result) => result.failed);
    const entityFailures = entityResults.filter((result) => result.failed);
    const processedCount = sourceResults.length - sourceFailures.length +
      entityResults.length - entityFailures.length;
    const attemptedCount = selectedSources.length +
      (discoverySource ? selectedEntities.length : 0);
    const discoveryMissing = !discoverySource && selectedEntities.length > 0;
    const pipelineSuccess = !discoveryMissing &&
      (attemptedCount === 0 || processedCount > 0);
    const totalInserted = sourceResults.reduce(
      (total, result) => total + result.inserted,
      0,
    );
    const entityInserted = entityResults.reduce(
      (total, result) => total + result.inserted,
      0,
    );
    return jsonResponse({
      success: pipelineSuccess,
      degraded: discoveryMissing || sourceFailures.length > 0 || entityFailures.length > 0,
      already_running: false,
      elapsed_ms: elapsedMs(startedAt),
      sources: sourceResults.length,
      sources_attempted: selectedSources.length,
      sources_processed: sourceResults.length - sourceFailures.length,
      source_ids: selectedSources.map((source) => source.id),
      failed_source_ids: sourceFailures.map((result) => result.source_id),
      empty_feeds: sourceResults.filter((result) => result.empty).length,
      source_failures: sourceFailures.length,
      inserted: totalInserted,
      entities_checked: entityResults.length,
      entities_attempted: discoverySource ? selectedEntities.length : 0,
      entities_processed: entityResults.length - entityFailures.length,
      failed_entity_ids: entityFailures.map((result) => result.entity_id),
      entity_failures: entityFailures.length,
      entity_items: entityInserted,
      entity_discovery_source_found: Boolean(discoverySource),
      details: sourceResults,
      entity_details: entityResults,
      timestamp: new Date().toISOString(),
    }, pipelineSuccess ? 200 : 502);
  } catch (error) {
    console.error("[ingest-news] Error:", error);
    return jsonResponse({
      error: "Ingestion failed",
      details: errorMessage(error),
      elapsed_ms: elapsedMs(startedAt),
    }, 500);
  } finally {
    if (serviceClient && leaseToken) {
      const { error: releaseError } = await serviceClient.rpc(
        "release_news_pipeline_lease",
        {
          p_pipeline: "ingest-news",
          p_lease_id: leaseToken,
        },
      );
      if (releaseError) {
        console.error(
          "[ingest-news] lease release failed:",
          releaseError.message,
        );
      }
    }
  }
});
