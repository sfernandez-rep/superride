// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import { createPublicKey, timingSafeEqual, verify } from 'node:crypto';

type Obj = Record<string, unknown>;
function obj(value: unknown): value is Obj {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function decodePart(part: string): Buffer {
  if (!part || !/^[A-Za-z0-9_-]+$/.test(part)) throw new Error('Invalid identity token');
  const decoded = Buffer.from(part, 'base64url');
  if (decoded.toString('base64url') !== part) throw new Error('Invalid identity token');
  return decoded;
}
function jsonPart(part: string): Obj {
  try {
    const parsed: unknown = JSON.parse(decodePart(part).toString('utf8'));
    if (obj(parsed)) return parsed;
  } catch { /* Use a generic message that never includes token contents. */ }
  throw new Error('Invalid identity token');
}
function equalSecret(a: string, b: string): boolean {
  const left = Buffer.from(a, 'utf8');
  const right = Buffer.from(b, 'utf8');
  return left.length === right.length && timingSafeEqual(left, right);
}

/**
 * Verify an OpenAI-issued OIDC ID token against trusted OpenAI JWKS supplied by
 * the caller. Fetching/refreshing JWKS, OAuth and storage are separate tasks.
 */
export function verifyOpenAiIdentity(token: string, jwks: unknown, audience: string,
  nonce: string, nowSeconds = Math.floor(Date.now() / 1000)): { subject: string; email?: string } {
  if (token.length > 32768 || !audience || !nonce || !obj(jwks) || !Array.isArray(jwks.keys))
    throw new Error('Invalid identity token');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Invalid identity token');
  const header = jsonPart(parts[0]);
  const claims = jsonPart(parts[1]);
  if (header.alg !== 'RS256' || typeof header.kid !== 'string' || !header.kid ||
      header.crit !== undefined || header.jku !== undefined || header.jwk !== undefined)
    throw new Error('Invalid identity token');
  const matching = jwks.keys.filter((key: unknown) => obj(key) && key.kid === header.kid &&
    key.kty === 'RSA' && (key.use === undefined || key.use === 'sig') &&
    (key.alg === undefined || key.alg === 'RS256') && typeof key.n === 'string' &&
    typeof key.e === 'string' && key.d === undefined);
  if (matching.length !== 1) throw new Error('Identity signing key unavailable');
  let valid = false;
  try {
    const key = createPublicKey({ key: matching[0] as JsonWebKey, format: 'jwk' });
    if ((key.asymmetricKeyDetails?.modulusLength ?? 0) >= 2048)
      valid = verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), key, decodePart(parts[2]));
  } catch { /* Do not disclose tokens, claims or keys in errors. */ }
  if (!valid) throw new Error('Invalid identity signature');
  const audiences = typeof claims.aud === 'string' ? [claims.aud] : claims.aud;
  if (claims.iss !== 'https://auth.openai.com' || !Array.isArray(audiences) ||
      !audiences.every(x => typeof x === 'string') || !audiences.includes(audience) ||
      (audiences.length > 1 && claims.azp !== audience) ||
      (claims.azp !== undefined && claims.azp !== audience) ||
      typeof claims.sub !== 'string' || !claims.sub ||
      typeof claims.nonce !== 'string' || !equalSecret(claims.nonce, nonce) ||
      !Number.isSafeInteger(claims.exp) || (claims.exp as number) <= nowSeconds ||
      !Number.isSafeInteger(claims.iat) || (claims.iat as number) > nowSeconds + 60 ||
      (claims.nbf !== undefined && (!Number.isSafeInteger(claims.nbf) || (claims.nbf as number) > nowSeconds + 60)))
    throw new Error('Identity claims are invalid');
  return { subject: claims.sub,
    ...(typeof claims.email === 'string' && claims.email_verified === true ? { email: claims.email } : {}) };
}
