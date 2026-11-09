// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { createServer, Server } from 'node:http';
import { verifyOpenAiIdentity } from './oidc-identity';
import type { CredentialVault, StoredGrant } from './credential-vault';

const AUTH_ORIGIN = 'https://auth.openai.com';
const RESOURCE = 'https://api.openai.com/v1';
const CALLBACK_PATH = '/auth/callback';
const MAX_JSON = 1024 * 1024;
type Obj = Record<string, unknown>;
function obj(value: unknown): value is Obj {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function random(): string { return randomBytes(32).toString('base64url'); }
function equal(a: string, b: string): boolean {
  const left = Buffer.from(a); const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
function text(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= 32768;
}

export interface ChatGptGrant {
  clientId: string;
  hostId: string;
  subject: string;
  email?: string;
  accessToken: string;
  refreshToken?: string;
  idToken: string;
  expiresIn: number;
  scopes: string[];
  sharing: boolean;
}

async function readJson(response: Response): Promise<Obj> {
  if (!response.ok || !response.body) throw new Error(`Authorization service returned HTTP ${response.status}`);
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.byteLength;
      if (size > MAX_JSON) throw new Error('Authorization response exceeds size limit');
      chunks.push(part.value);
    }
  } finally { reader.releaseLock(); }
  let value: unknown;
  try { value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); }
  catch { throw new Error('Invalid authorization response'); }
  if (!obj(value)) throw new Error('Invalid authorization response');
  return value;
}

export interface AuthOptions {
  hostId: string;
  clientId?: string;
  expectedSubject?: string;
  expectedSubjectHash?: string;
  // Persist the newly issued registration before exchanging a short-lived code.
  onRegistration: (clientId: string) => Promise<void>;
  fetch?: typeof globalThis.fetch;
}

/**
 * Start a loopback OAuth attempt. The caller must explicitly open authorizeUrl
 * in the system browser and must store the resulting grant with OS protection.
 * This module does not open a browser, persist credentials, or send an AI prompt.
 */
export async function beginChatGptAuthorization(options: AuthOptions): Promise<{
  authorizeUrl: string; result: Promise<ChatGptGrant>; cancel: () => void;
}> {
  if (!/^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(options.hostId))
    throw new Error('A persistent UUIDv4 host ID is required');
  if (options.clientId !== undefined && (!/^[A-Za-z0-9._-]{1,256}$/.test(options.clientId) || options.clientId === 'dynamic_agent_client'))
    throw new Error('Invalid registered client');
  if (options.expectedSubjectHash !== undefined && !/^[a-f0-9]{64}$/.test(options.expectedSubjectHash))
    throw new Error('Invalid expected account identity');
  const request = options.fetch ?? globalThis.fetch;
  const state = random(), nonce = random(), verifier = random();
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  let server: Server;
  let settled = false;
  let accepting = true;
  const abort = new AbortController();
  let resolveResult!: (grant: ChatGptGrant) => void;
  let rejectResult!: (error: Error) => void;
  const result = new Promise<ChatGptGrant>((resolve, reject) => { resolveResult = resolve; rejectResult = reject; });
  // A callback can arrive before the UI has attached its completion handler.
  void result.catch(() => {});
  const stop = (error?: Error) => {
    if (settled) return;
    settled = true;
    accepting = false;
    clearTimeout(timeout);
    server.close();
    if (error) abort.abort();
    if (error) rejectResult(error);
  };
  const timeout = setTimeout(() => stop(new Error('Authorization timed out')), 5 * 60 * 1000);
  timeout.unref();
  server = createServer((incoming, response) => {
    const address = incoming.socket.remoteAddress;
    let url: URL;
    try { url = new URL(incoming.url ?? '/', 'http://127.0.0.1'); }
    catch { response.writeHead(400); response.end(); return; }
    if (!accepting || incoming.method !== 'GET' || address !== '127.0.0.1' || url.pathname !== CALLBACK_PATH ||
        ['state', 'code', 'client_id', 'error'].some(key => url.searchParams.getAll(key).length > 1) ||
        !equal(url.searchParams.get('state') ?? '', state)) {
      response.writeHead(400, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
      response.end('Invalid authorization response.');
      return;
    }
    const code = url.searchParams.get('code');
    const receivedId = url.searchParams.get('client_id');
    const clientId = options.clientId ?? receivedId;
    if (url.searchParams.has('error') || !text(code) || !text(clientId) || !/^[A-Za-z0-9._-]{1,256}$/.test(clientId) ||
        clientId === 'dynamic_agent_client' || (options.clientId && receivedId && receivedId !== options.clientId)) {
      response.writeHead(400, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
      response.end('Authorization was declined or incomplete. Return to SuperR.');
      stop(new Error('Authorization declined or incomplete'));
      return;
    }
    response.writeHead(200, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
    response.end('Authorization received. Return to SuperR.');
    // Stop accepting callbacks before asynchronous token exchange.
    accepting = false;
    server.close();
    void (async () => {
      try {
        if (!options.clientId) await options.onRegistration(clientId);
        const redirectUri = `http://127.0.0.1:${port}${CALLBACK_PATH}`;
        const form = new URLSearchParams({ grant_type: 'authorization_code', client_id: clientId,
          code, code_verifier: verifier, redirect_uri: redirectUri, resource: RESOURCE });
        const token = await readJson(await request(`${AUTH_ORIGIN}/api/accounts/oauth/token`, {
          method: 'POST', body: form, redirect: 'error', signal: AbortSignal.any([abort.signal, AbortSignal.timeout(20000)]),
        }));
        const discovery = await readJson(await request(`${AUTH_ORIGIN}/.well-known/openid-configuration`,
          { redirect: 'error', signal: AbortSignal.any([abort.signal, AbortSignal.timeout(20000)]) }));
        if (discovery.issuer !== AUTH_ORIGIN || !text(discovery.jwks_uri)) throw new Error('Invalid identity issuer');
        const jwksUrl = new URL(discovery.jwks_uri);
        if (jwksUrl.origin !== AUTH_ORIGIN || jwksUrl.username || jwksUrl.password) throw new Error('Invalid identity key endpoint');
        const jwks = await readJson(await request(jwksUrl.toString(), { redirect: 'error', signal: AbortSignal.any([abort.signal, AbortSignal.timeout(20000)]) }));
        if (!text(token.id_token) || !text(token.access_token) ||
            (token.refresh_token !== undefined && !text(token.refresh_token)) ||
            typeof token.token_type !== 'string' || token.token_type.toLowerCase() !== 'bearer' ||
            typeof token.expires_in !== 'number' || !Number.isFinite(token.expires_in) || token.expires_in <= 0 ||
            typeof token.scope !== 'string') throw new Error('Incomplete authorization grant');
        const identity = verifyOpenAiIdentity(token.id_token, jwks, clientId, nonce);
        if (options.expectedSubject && identity.subject !== options.expectedSubject) throw new Error('Account identity changed');
        if (options.expectedSubjectHash && createHash('sha256').update(identity.subject).digest('hex') !== options.expectedSubjectHash)
          throw new Error('Account identity changed');
        const scopes = token.scope.split(/\s+/).filter(Boolean);
        if (settled) return;
        stop();
        resolveResult({ clientId, hostId: options.hostId, ...identity, accessToken: token.access_token,
          ...(text(token.refresh_token) ? { refreshToken: token.refresh_token } : {}),
          idToken: token.id_token, expiresIn: token.expires_in,
          scopes, sharing: scopes.includes('chatgpt.tokens.use.direct') });
      } catch { stop(new Error('Authorization could not be verified')); }
    })();
  });
  try {
    await new Promise<void>((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', () => { server.removeListener('error', reject); resolve(); });
    });
  } catch {
    clearTimeout(timeout);
    throw new Error('Could not start local authorization listener');
  }
  const address = server.address();
  if (!address || typeof address === 'string') { stop(); throw new Error('Invalid local listener'); }
  const port = address.port;
  const redirectUri = `http://127.0.0.1:${port}${CALLBACK_PATH}`;
  const params = new URLSearchParams({ client_id: options.clientId ?? 'dynamic_agent_client',
    ext_agent_host_id: options.hostId, response_type: 'code', redirect_uri: redirectUri,
    scope: 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct',
    resource: RESOURCE, state, nonce, code_challenge_method: 'S256', code_challenge: challenge });
  if (!options.clientId) params.set('agent_name_hint', 'SuperR');
  return { authorizeUrl: `${AUTH_ORIGIN}/api/accounts/authorize?${params}`, result,
    cancel: () => stop(new Error('Authorization cancelled')) };
}

/** Rotate a refresh token while holding the vault's cross-process profile lock. */
export async function refreshChatGptGrant(vault: CredentialVault, profileId: string,
  request: typeof globalThis.fetch = globalThis.fetch): Promise<StoredGrant> {
  return vault.update(profileId, async current => {
    if (!current.refreshToken) throw new Error('This account needs to sign in again');
    const form = new URLSearchParams({ grant_type: 'refresh_token', client_id: current.clientId,
      refresh_token: current.refreshToken, resource: RESOURCE });
    const token = await readJson(await request(`${AUTH_ORIGIN}/api/accounts/oauth/token`, {
      method: 'POST', body: form, redirect: 'error', signal: AbortSignal.timeout(20000),
    }));
    if (!text(token.access_token) || !text(token.refresh_token) ||
        typeof token.token_type !== 'string' || token.token_type.toLowerCase() !== 'bearer' ||
        typeof token.expires_in !== 'number' || !Number.isFinite(token.expires_in) || token.expires_in <= 0 ||
        (token.scope !== undefined && typeof token.scope !== 'string'))
      throw new Error('Incomplete refresh response');
    const scopes = typeof token.scope === 'string' ? token.scope.split(/\s+/).filter(Boolean) : current.scopes;
    return { ...current, accessToken: token.access_token, refreshToken: token.refresh_token,
      expiresIn: token.expires_in, scopes, sharing: scopes.includes('chatgpt.tokens.use.direct'), savedAt: Date.now() };
  });
}

/** Returns whether server-side revocation was confirmed; caller should report false. */
export async function signOutChatGpt(vault: CredentialVault, profileId: string,
  clearWithoutConfirmation: boolean, request: typeof globalThis.fetch = globalThis.fetch): Promise<boolean> {
  return vault.removeAfter(profileId, async current => {
    if (!current.refreshToken) return false;
    try {
      const discovery = await readJson(await request(`${AUTH_ORIGIN}/.well-known/openid-configuration`,
        { redirect: 'error', signal: AbortSignal.timeout(20000) }));
      if (discovery.issuer !== AUTH_ORIGIN || !text(discovery.revocation_endpoint)) throw new Error('Invalid identity issuer');
      const endpoint = new URL(discovery.revocation_endpoint);
      if (endpoint.origin !== AUTH_ORIGIN || endpoint.username || endpoint.password) throw new Error('Invalid revocation endpoint');
      const body = new URLSearchParams({ token: current.refreshToken, token_type_hint: 'refresh_token', client_id: current.clientId });
      const response = await request(endpoint.toString(), { method: 'POST', body, redirect: 'error', signal: AbortSignal.timeout(20000) });
      if (response.status !== 200) throw new Error('Revocation was not confirmed');
      return true;
    } catch {
      if (!clearWithoutConfirmation) throw new Error('Revocation was not confirmed; local credentials retained');
      return false;
    }
  });
}
