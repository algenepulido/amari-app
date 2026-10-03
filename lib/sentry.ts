// Sentry monitoring — @sentry/react-native is NOT installed yet.
// Every export here is a guarded no-op until the dependency is added
// (npx expo install @sentry/react-native) AND an EXPO_PUBLIC_SENTRY_DSN env var is set.
// Expo only inlines EXPO_PUBLIC_-prefixed variables into the client bundle, so the DSN
// must use that prefix or it is undefined at runtime (HO-14). No hard import of
// @sentry/react-native anywhere in this file — only a guarded dynamic require, so the
// app builds and runs fine without it.

type SentryClient = {
  init: (options: Record<string, unknown>) => void;
  captureException: (error: unknown, context?: Record<string, unknown>) => void;
};

let sentryClient: SentryClient | null = null;

/**
 * Initializes Sentry if (a) a DSN is configured via env var and (b)
 * @sentry/react-native can be required. Safe no-op otherwise — never throws.
 */
export function initSentry(): void {
  if (sentryClient) return; // already initialized

  const dsn = process.env.EXPO_PUBLIC_SENTRY_DSN;
  if (!dsn) return;

  try {
    const Sentry = require('@sentry/react-native') as SentryClient;
    Sentry.init({
      dsn,
      tracesSampleRate: 0.2,
      profilesSampleRate: 0.1,
      environment: __DEV__ ? 'development' : 'production',
      enabled: !__DEV__,
    });
    sentryClient = Sentry;
  } catch {
    // @sentry/react-native isn't installed (or init failed) — stay a no-op.
    sentryClient = null;
  }
}

/** True once initSentry() has successfully wired up an active Sentry client. */
export function isSentryActive(): boolean {
  return sentryClient !== null;
}

/**
 * Passthrough to Sentry's captureException when a client is active.
 * Safe no-op (never throws) when Sentry is absent or uninitialized —
 * callers (e.g. reportError) should fall back to console logging themselves.
 */
export function captureException(error: unknown, context?: Record<string, unknown>): void {
  if (!sentryClient) return;

  try {
    sentryClient.captureException(error, context);
  } catch {
    // Telemetry must never crash the app.
  }
}
