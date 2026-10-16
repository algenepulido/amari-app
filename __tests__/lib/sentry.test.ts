import { scrubSentryEvent } from '@/lib/sentry';

// Confirms the beforeSend scrubber keeps personal data out of Sentry events: user identity
// beyond an opaque id, authorization headers, and anything shaped like an email or a bearer
// token in the message, the exception values and the breadcrumbs.
describe('scrubSentryEvent', () => {
  it('drops user identity beyond the id', () => {
    const event = scrubSentryEvent({ user: { id: 'u1', email: 'alice@example.com', username: 'alice' } });
    expect(event?.user).toEqual({ id: 'u1' });
  });

  it('redacts an email in the message', () => {
    const event = scrubSentryEvent({ message: 'redeem failed for alice@example.com' });
    expect(event?.message).toBe('redeem failed for [email]');
  });

  it('redacts a bearer token in an exception value', () => {
    const event = scrubSentryEvent({ exception: { values: [{ value: 'Bearer abc.def-123 was rejected' }] } });
    expect(event?.exception.values[0].value).toBe('Bearer [redacted] was rejected');
  });

  it('redacts the authorization header but keeps other headers', () => {
    const event = scrubSentryEvent({
      request: { headers: { Authorization: 'Bearer xyz', 'content-type': 'application/json' } },
    });
    expect(event?.request.headers.Authorization).toBe('[redacted]');
    expect(event?.request.headers['content-type']).toBe('application/json');
  });

  it('redacts an email in a breadcrumb message', () => {
    const event = scrubSentryEvent({ breadcrumbs: [{ message: 'invite sent to bob@amari.test' }] });
    expect(event?.breadcrumbs[0].message).toBe('invite sent to [email]');
  });

  it('is a safe no-op for a null event', () => {
    expect(scrubSentryEvent(null)).toBeNull();
  });
});
