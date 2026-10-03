import { supabase } from './supabase';

type AuthCallbackResult =
  | { handled: false }
  | { handled: true; sessionEstablished: boolean };

function collectParams(url: string) {
  const params = new URLSearchParams();
  const [withoutHash, hash = ''] = url.split('#');
  const query = withoutHash.includes('?') ? withoutHash.slice(withoutHash.indexOf('?') + 1) : '';

  for (const source of [query, hash]) {
    const searchParams = new URLSearchParams(source);
    searchParams.forEach((value, key) => params.set(key, value));
  }

  return params;
}

export async function completeAuthFromUrl(url: string): Promise<AuthCallbackResult> {
  if (!url.includes('auth-callback')) {
    return { handled: false };
  }

  const params = collectParams(url);
  const error = params.get('error') || params.get('error_code');

  if (error) {
    throw new Error(params.get('error_description') || error);
  }

  // HO-12: do not accept a raw access_token / refresh_token from the URL.
  // The previous version handed those straight to supabase.auth.setSession, so any
  // crafted amari://auth-callback#access_token=...&refresh_token=... link (opened from
  // another app, a message, or a QR code) could sign the app into an attacker-controlled
  // session. The only session-establishing inputs accepted now are:
  //   - the PKCE `code`, which exchangeCodeForSession verifies against a code_verifier
  //     stored on this device, so a forged code cannot complete; and
  //   - the email `token_hash`, which verifyOtp validates server-side against the address
  //     the link was issued to.
  // Both are bound to this device or to a server-issued secret, so a forged link cannot
  // establish a session.
  const code = params.get('code');
  if (code) {
    const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
    if (exchangeError) throw exchangeError;
    return { handled: true, sessionEstablished: true };
  }

  const tokenHash = params.get('token_hash');
  const type = params.get('type') || 'email';

  if (tokenHash) {
    const { error: verifyError } = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type: type as 'email' | 'signup' | 'magiclink' | 'recovery' | 'invite' | 'email_change',
    });

    if (verifyError) throw verifyError;
    return { handled: true, sessionEstablished: true };
  }

  return { handled: true, sessionEstablished: false };
}
