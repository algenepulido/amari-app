// @ts-nocheck
// AMARI intelligence feed: reputation-prioritised, budget-bounded article
// enrichment. A database lease prevents overlapping workers and each model
// call is transactionally reserved before dispatch.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  buildPrompt,
  costUsd,
  HARD_MONTHLY_BUDGET_USD,
  MAX_OUTPUT_TOKENS,
  pacingAllowance,
  parseClassifications,
  promptReservationUsd,
  type Classification,
  type MeterRates,
  type PromptArticle,
} from './core.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PIPELINE_SECRET = Deno.env.get('NEWS_PIPELINE_SECRET') ?? '';

const LLM_PROVIDER = (Deno.env.get('LLM_PROVIDER') ?? 'anthropic').toLowerCase();
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? '';
const OPENAI_BASE_URL = (Deno.env.get('OPENAI_BASE_URL') ?? 'https://api.openai.com/v1').replace(/\/$/, '');
const OPENAI_MODEL = 'gpt-4o-mini-2024-07-18';

const ANTHROPIC_MODEL = 'claude-haiku-4-5-20251001';
const BATCH_SIZE = 10;
const MAX_BATCHES_PER_RUN = 2;
const LLM_CONCURRENCY = 5;
const LLM_TIMEOUT_MS = 25_000;
const RELEVANCE_FLOOR = 25;
const LEASE_SECONDS = 180;
const MAX_QUEUE_SIZE = BATCH_SIZE * MAX_BATCHES_PER_RUN;

const METER_RATES: Record<string, MeterRates> = {
  anthropic: { input: 1.0, output: 5.0 },
  openai: { input: 0.6, output: 2.4 },
};
const ACTIVE_RATES = METER_RATES[LLM_PROVIDER] ?? METER_RATES.anthropic;
const ACTIVE_API_KEY = LLM_PROVIDER === 'openai' ? OPENAI_API_KEY : ANTHROPIC_API_KEY;

interface BudgetState {
  spentUsd: number;
  reservedUsd: number;
}

interface PendingCounts {
  eligible: number;
  stale: number;
}

interface ClassificationResult {
  classifications: Classification[];
  inputTokens: number;
  outputTokens: number;
}

class LlmDispatchError extends Error {
  dispatched: boolean;

  constructor(message: string, dispatched: boolean, cause?: unknown) {
    super(message, { cause });
    this.name = 'LlmDispatchError';
    this.dispatched = dispatched;
  }
}

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
  const {
    data: { user },
    error: userError,
  } = await memberClient.auth.getUser(accessToken);

  if (userError || !user) return false;

  const { data: isAdmin } = await memberClient.rpc('is_admin');

  return Boolean(isAdmin);
}

async function getBudgetState(
  serviceClient: ReturnType<typeof createClient>,
  month: string,
): Promise<BudgetState> {
  const { data, error } = await serviceClient
    .from('news_ai_spend')
    .select('spent_usd, reserved_usd')
    .eq('month', month)
    .maybeSingle();

  if (error) throw error;
  return {
    spentUsd: Number(data?.spent_usd ?? 0),
    reservedUsd: Number(data?.reserved_usd ?? 0),
  };
}

async function getPendingCounts(
  serviceClient: ReturnType<typeof createClient>,
  cutoffIso: string,
): Promise<PendingCounts> {
  const eligibleFilter = `published_at.gt.${cutoffIso},and(published_at.is.null,ingested_at.gt.${cutoffIso})`;
  const staleFilter = `published_at.lte.${cutoffIso},and(published_at.is.null,ingested_at.lte.${cutoffIso})`;

  const [eligibleResult, staleResult] = await Promise.all([
    serviceClient
      .from('news_articles')
      .select('id', { count: 'planned', head: true })
      .eq('status', 'pending')
      .or(eligibleFilter),
    serviceClient
      .from('news_articles')
      .select('id', { count: 'planned', head: true })
      .eq('status', 'pending')
      .or(staleFilter),
  ]);

  if (eligibleResult.error) throw eligibleResult.error;
  if (staleResult.error) throw staleResult.error;

  return {
    eligible: eligibleResult.count ?? 0,
    stale: staleResult.count ?? 0,
  };
}

function pacingReport(
  pacing: ReturnType<typeof pacingAllowance>,
  budget: BudgetState,
) {
  return {
    month: pacing.month,
    elapsed_month_fraction: Number(pacing.elapsedFraction.toFixed(8)),
    allowed_usd_to_date: Number(pacing.allowedUsd.toFixed(8)),
    spent_usd: Number(budget.spentUsd.toFixed(8)),
    reserved_usd: Number(budget.reservedUsd.toFixed(8)),
    available_usd: Number(
      Math.max(0, pacing.allowedUsd - budget.spentUsd - budget.reservedUsd).toFixed(8),
    ),
  };
}

async function classifyArticle(prompt: string): Promise<ClassificationResult> {
  let dispatched = false;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), LLM_TIMEOUT_MS);

  try {
    if (LLM_PROVIDER === 'openai') {
      const requestBody = JSON.stringify({
        model: OPENAI_MODEL,
        max_tokens: MAX_OUTPUT_TOKENS,
        messages: [{ role: 'user', content: prompt }],
      });
      dispatched = true;
      const response = await fetch(`${OPENAI_BASE_URL}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${OPENAI_API_KEY}`,
        },
        body: requestBody,
        signal: controller.signal,
      });

      if (!response.ok) {
        const body = await response.text();
        throw new Error(`LLM API ${response.status}: ${body.slice(0, 200)}`);
      }

      const data = await response.json();
      const inputTokens = Number(data?.usage?.prompt_tokens);
      const outputTokens = Number(data?.usage?.completion_tokens);
      if (!Number.isFinite(inputTokens) || inputTokens <= 0 || !Number.isFinite(outputTokens) || outputTokens < 0) {
        throw new Error('LLM response omitted reliable usage data');
      }

      return {
        classifications: parseClassifications(data?.choices?.[0]?.message?.content ?? ''),
        inputTokens,
        outputTokens,
      };
    }

    const requestBody = JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: MAX_OUTPUT_TOKENS,
      messages: [{ role: 'user', content: prompt }],
    });
    dispatched = true;
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: requestBody,
      signal: controller.signal,
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Anthropic API ${response.status}: ${body.slice(0, 200)}`);
    }

    const data = await response.json();
    const inputTokens = Number(data?.usage?.input_tokens);
    const outputTokens = Number(data?.usage?.output_tokens);
    if (!Number.isFinite(inputTokens) || inputTokens <= 0 || !Number.isFinite(outputTokens) || outputTokens < 0) {
      throw new Error('Anthropic response omitted reliable usage data');
    }

    const text = (data?.content ?? [])
      .filter((block: Record<string, unknown>) => block.type === 'text')
      .map((block: Record<string, unknown>) => block.text)
      .join('\n');

    return {
      classifications: parseClassifications(text),
      inputTokens,
      outputTokens,
    };
  } catch (error) {
    if (error instanceof LlmDispatchError) throw error;
    throw new LlmDispatchError(
      error instanceof Error ? error.message : String(error),
      dispatched,
      error,
    );
  } finally {
    clearTimeout(timeout);
  }
}

async function mapWithConcurrency<T, R>(
  items: readonly T[],
  concurrency: number,
  worker: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let nextIndex = 0;
  const runWorker = async () => {
    while (true) {
      const index = nextIndex++;
      if (index >= items.length) return;
      results[index] = await worker(items[index]);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(concurrency, items.length) }, runWorker),
  );
  return results;
}

Deno.serve(async (req: Request) => {
  try {
    if (!(await isAuthorized(req))) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    if (!ACTIVE_API_KEY) {
      return jsonResponse(
        { error: `No API key configured for LLM provider "${LLM_PROVIDER}"` },
        500,
      );
    }

    const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: leaseId, error: leaseError } = await serviceClient.rpc(
      'try_acquire_news_pipeline_lease',
      { p_pipeline: 'enrich-news', p_lease_seconds: LEASE_SECONDS },
    );

    if (leaseError) throw leaseError;
    if (!leaseId) {
      return jsonResponse({
        success: true,
        enriched: 0,
        skipped: 'already_running',
        lease: { acquired: false, duration_seconds: LEASE_SECONDS },
        message: 'Another enrichment invocation holds the pipeline lease.',
      });
    }

    const finish = async (payload: Record<string, unknown>, status = 200) => {
      const { data: released, error: releaseError } = await serviceClient.rpc(
        'release_news_pipeline_lease',
        { p_pipeline: 'enrich-news', p_lease_id: leaseId },
      );
      if (releaseError) {
        console.error('[enrich-news] Lease release failed:', releaseError.message);
      }

      return jsonResponse(
        {
          ...payload,
          lease: {
            acquired: true,
            duration_seconds: LEASE_SECONDS,
            released: released === true,
          },
        },
        status,
      );
    };

    try {
      const startedAt = new Date();
      const cutoffIso = new Date(startedAt.getTime() - 14 * 24 * 60 * 60 * 1_000).toISOString();
      let pacing = pacingAllowance(startedAt);
      let [pendingCounts, budget] = await Promise.all([
        getPendingCounts(serviceClient, cutoffIso),
        getBudgetState(serviceClient, pacing.month),
      ]);

      if (budget.spentUsd >= HARD_MONTHLY_BUDGET_USD) {
        return await finish({
          success: true,
          enriched: 0,
          skipped: 'monthly_budget_reached',
          spent_usd: budget.spentUsd,
          budget_usd: HARD_MONTHLY_BUDGET_USD,
          eligible_pending: pendingCounts.eligible,
          stale_pending: pendingCounts.stale,
          pending_counts_approximate: true,
          pacing: pacingReport(pacing, budget),
          reservation: { attempted: 0, denied: 0, settled: 0, released: 0, retained: 0 },
          message: `Monthly AI budget of $${HARD_MONTHLY_BUDGET_USD.toFixed(2)} reached; enrichment paused until next month.`,
        });
      }

      if (budget.spentUsd + budget.reservedUsd >= pacing.allowedUsd) {
        return await finish({
          success: true,
          enriched: 0,
          skipped: 'pacing_limit_reached',
          spent_usd: budget.spentUsd,
          budget_usd: HARD_MONTHLY_BUDGET_USD,
          eligible_pending: pendingCounts.eligible,
          stale_pending: pendingCounts.stale,
          pending_counts_approximate: true,
          pacing: pacingReport(pacing, budget),
          reservation: { attempted: 0, denied: 0, settled: 0, released: 0, retained: 0 },
          message: 'Enrichment is paced to the current UTC month allowance.',
        });
      }

      const { data: pending, error: pendingError } = await serviceClient.rpc(
        'get_pending_for_enrichment',
        { p_limit: MAX_QUEUE_SIZE },
      );
      if (pendingError) throw pendingError;

      if (!pending?.length) {
        return await finish({
          success: true,
          enriched: 0,
          message: 'No pending articles',
          eligible_pending: pendingCounts.eligible,
          stale_pending: pendingCounts.stale,
          pending_counts_approximate: true,
          pacing: pacingReport(pacing, budget),
          reservation: { attempted: 0, denied: 0, settled: 0, released: 0, retained: 0 },
        });
      }

      let published = 0;
      let hidden = 0;
      let failed = 0;
      let stoppedReason: string | null = null;
      const reservation = {
        attempted: 0,
        denied: 0,
        settled: 0,
        released: 0,
        retained: 0,
        requested_usd: 0,
        settled_usd: 0,
        released_usd: 0,
        retained_usd: 0,
      };

      batchLoop:
      for (let offset = 0; offset < pending.length; offset += BATCH_SIZE) {
        const batch: PromptArticle[] = pending.slice(offset, offset + BATCH_SIZE).map((row) => ({
          id: row.id,
          title: row.title,
          snippet: row.snippet,
          source: row.source_name ?? 'Unknown',
        }));
        const stopReasons = await mapWithConcurrency(
          batch,
          LLM_CONCURRENCY,
          async (article): Promise<string | null> => {
          const { data: renewed, error: renewError } = await serviceClient.rpc(
            'renew_news_pipeline_lease',
            { p_pipeline: 'enrich-news', p_lease_id: leaseId, p_lease_seconds: LEASE_SECONDS },
          );
          if (renewError || renewed !== true) {
            console.error('[enrich-news] Lease renewal failed:', renewError?.message ?? 'lease ownership lost');
            return 'lease_lost';
          }
          const prompt = buildPrompt(article);
          const requestedUsd = promptReservationUsd(prompt, ACTIVE_RATES);
          pacing = pacingAllowance(new Date());

          reservation.attempted += 1;
          reservation.requested_usd += requestedUsd;
          const { data: reservationId, error: reservationError } = await serviceClient.rpc(
            'reserve_news_ai_budget',
            {
              p_month: pacing.month,
              p_requested_usd: Number(requestedUsd.toFixed(8)),
              p_allowed_usd: Number(pacing.allowedUsd.toFixed(8)),
            },
          );

          if (reservationError) {
            console.error('[enrich-news] Budget reservation failed:', reservationError.message);
            failed += 1;
            return 'reservation_error';
          }

          if (!reservationId) {
            reservation.denied += 1;
            return 'pacing_or_budget_limit';
          }

          let result: ClassificationResult;
          try {
            result = await classifyArticle(prompt);
          } catch (error) {
            console.error(`[enrich-news] Article ${article.id} classification failed:`, error);
            failed += 1;

            if (error instanceof LlmDispatchError && !error.dispatched) {
              const { data: released, error: releaseError } = await serviceClient.rpc(
                'release_news_ai_budget_reservation',
                { p_reservation_id: reservationId },
              );
              if (!releaseError && released === true) {
                reservation.released += 1;
                reservation.released_usd += requestedUsd;
              } else {
                reservation.retained += 1;
                reservation.retained_usd += requestedUsd;
              }
            } else {
              reservation.retained += 1;
              reservation.retained_usd += requestedUsd;
            }

            return error instanceof LlmDispatchError && error.dispatched
              ? 'ambiguous_post_dispatch_failure'
              : 'pre_dispatch_failure';
          }

          const actualUsd = costUsd(result.inputTokens, result.outputTokens, ACTIVE_RATES);
          const { data: settled, error: settleError } = await serviceClient.rpc(
            'settle_news_ai_budget',
            {
              p_reservation_id: reservationId,
              p_input_tokens: result.inputTokens,
              p_output_tokens: result.outputTokens,
              p_actual_usd: Number(actualUsd.toFixed(8)),
            },
          );

          if (settleError || settled !== true) {
            console.error(
              `[enrich-news] Budget settlement failed for article ${article.id}; update withheld:`,
              settleError?.message ?? 'reservation was not active',
            );
            reservation.retained += 1;
            reservation.retained_usd += requestedUsd;
            failed += 1;
            return 'settlement_unknown';
          }

          reservation.settled += 1;
          reservation.settled_usd += actualUsd;
          const classifications = result.classifications.filter((entry) => entry.id === article.id);
          if (classifications.length !== 1) {
            console.warn(
              `[enrich-news] Article ${article.id} returned ${classifications.length} matching classifications`,
            );
            failed += 1;
            return null;
          }

          const classification = classifications[0];
          const status = classification.relevance >= RELEVANCE_FLOOR ? 'published' : 'hidden';
          const { error: updateError } = await serviceClient
            .from('news_articles')
            .update({
              topics: classification.topics,
              regions: classification.regions,
              relevance: classification.relevance,
              summary: classification.summary || null,
              status,
              updated_at: new Date().toISOString(),
            })
            .eq('id', classification.id)
            .eq('status', 'pending');

          if (updateError) {
            console.error(`[enrich-news] Update failed for article ${classification.id}:`, updateError.message);
            failed += 1;
          } else if (status === 'published') {
            published += 1;
          } else {
            hidden += 1;
          }
            return null;
          },
        );
        const batchStopReason = stopReasons.find((reason) => reason !== null);
        if (batchStopReason) {
          stoppedReason = batchStopReason;
          break batchLoop;
        }
      }

      pacing = pacingAllowance(new Date());
      budget = await getBudgetState(serviceClient, pacing.month);
      pendingCounts = await getPendingCounts(serviceClient, cutoffIso);

      return await finish({
        success: true,
        published,
        hidden,
        failed,
        remaining_estimate: Math.max(0, pending.length - published - hidden - failed),
        spent_usd_this_month: Number(budget.spentUsd.toFixed(8)),
        budget_usd: HARD_MONTHLY_BUDGET_USD,
        eligible_pending: pendingCounts.eligible,
        stale_pending: pendingCounts.stale,
        pending_counts_approximate: true,
        pacing: pacingReport(pacing, budget),
        reservation: {
          ...reservation,
          requested_usd: Number(reservation.requested_usd.toFixed(8)),
          settled_usd: Number(reservation.settled_usd.toFixed(8)),
          released_usd: Number(reservation.released_usd.toFixed(8)),
          retained_usd: Number(reservation.retained_usd.toFixed(8)),
        },
        stopped_reason: stoppedReason,
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      console.error('[enrich-news] Error:', error);
      return await finish(
        { error: 'Enrichment failed', details: error instanceof Error ? error.message : String(error) },
        500,
      );
    }
  } catch (error) {
    console.error('[enrich-news] Error before lease acquisition:', error);
    return jsonResponse(
      { error: 'Enrichment failed', details: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
