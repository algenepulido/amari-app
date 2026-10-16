// Sentry monitoring. @sentry/react-native is installed and wired through the Expo config
// plugin. This file keeps a guarded dynamic require so the app still builds and runs if the
// package is ever absent, and never throws. The DSN must use the EXPO_PUBLIC_ prefix, because
// Expo only inlines those into the client bundle, or it is undefined at runtime (HO-14).
// Events are scrubbed of user identity, emails and bearer tokens before they leave the device.

type SentryClient = {
  init: (options: Record<string, unknown>) => void;
  captureException: (error: unknown, context?: Record<string, unknown>) => void;
};

let sentryClient: SentryClient | null = null;

// Strip anything that could carry personal data before an event is sent: user identity beyond
// an opaque id, authorization headers and cookies, and anything shaped like an email or a bearer
// token in the message, the exception values and the breadcrumbs.
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const BEARER_RE = /Bearer\s+[A-Za-z0-9._-]+/g;

function redactText(value: unknown): unknown {
  return typeof value === 'string'
    ? value.replace(EMAIL_RE, '[email]').replace(BEARER_RE, 'Bearer [redacted]')
    : value;
}

export function scrubSentryEvent(event: Record<string, any> | null): Record<string, any> | null {
  if (!event) return event;
  if (event.user) {
    event.user = event.user.id ? { id: event.user.id } : undefined;
  }
  const headers = event.request?.headers;
  if (headers && typeof headers === 'object') {
    for (const key of Object.keys(headers)) {
      if (/authorization|cookie/i.test(key)) headers[key] = '[redacted]';
    }
  }
  if (event.request?.cookies) event.request.cookies = undefined;
  if (typeof event.message === 'string') event.message = redactText(event.message);
  for (const ex of event.exception?.values ?? []) {
    if (typeof ex.value === 'string') ex.value = redactText(ex.value);
  }
  for (const crumb of event.breadcrumbs ?? []) {
    if (typeof crumb.message === 'string') crumb.message = redactText(crumb.message);
  }
  return event;
}

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
      sendDefaultPii: false,
      beforeSend: scrubSentryEvent,
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
