const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { beginChatGptAuthorization } = require('../../src/node/desktop/src/main/superr-agent/chatgpt-auth');
const hostId = 'urn:uuid:00000000-0000-4000-8000-000000000000';
const clientId = 'oaiapp_test';
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');

test('OAuth loopback validates state, PKCE, issued client and signed identity without network', async () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'key', alg: 'RS256', use: 'sig' };
  let auth, registered, sawPkce = false;
  const mockFetch = async (url, opts) => {
    if (url.endsWith('/oauth/token')) {
      const params = opts.body;
      sawPkce = params.get('client_id') === clientId && params.get('redirect_uri') === auth.searchParams.get('redirect_uri') &&
        crypto.createHash('sha256').update(params.get('code_verifier')).digest('base64url') === auth.searchParams.get('code_challenge');
      const now = Math.floor(Date.now() / 1000);
      const signed = `${encode({ alg: 'RS256', kid: 'key' })}.${encode({ iss: 'https://auth.openai.com', aud: clientId,
        sub: 'user-1', nonce: auth.searchParams.get('nonce'), iat: now, exp: now + 60 })}`;
      const id = `${signed}.${crypto.sign('RSA-SHA256', Buffer.from(signed), privateKey).toString('base64url')}`;
      return Response.json({ id_token: id, access_token: 'access', refresh_token: 'refresh', token_type: 'Bearer', expires_in: 3600,
        scope: 'openid chatgpt.tokens.use.direct' });
    }
    if (url.endsWith('/openid-configuration')) return Response.json({ issuer: 'https://auth.openai.com', jwks_uri: 'https://auth.openai.com/jwks' });
    if (url.endsWith('/jwks')) return Response.json({ keys: [jwk] });
    throw Error('Unexpected URL');
  };
  const flow = await beginChatGptAuthorization({ hostId, onRegistration: async id => { registered = id; }, fetch: mockFetch });
  auth = new URL(flow.authorizeUrl);
  assert.equal(auth.searchParams.get('client_id'), 'dynamic_agent_client');
  const callback = new URL(auth.searchParams.get('redirect_uri'));
  callback.searchParams.set('state', 'wrong');
  callback.searchParams.set('code', 'test-code');
  callback.searchParams.set('client_id', clientId);
  assert.equal((await fetch(callback)).status, 400);
  callback.searchParams.set('state', auth.searchParams.get('state'));
  assert.equal((await fetch(callback)).status, 200);
  const grant = await flow.result;
  assert.equal(registered, clientId);
  assert.equal(sawPkce, true);
  assert.equal(grant.subject, 'user-1');
  assert.equal(grant.sharing, true);
});

test('cancellation closes the local listener and does not open a browser', async () => {
  const flow = await beginChatGptAuthorization({ hostId, onRegistration: async () => {} });
  const rejected = assert.rejects(flow.result, /cancelled/);
  flow.cancel();
  await rejected;
});

test('mismatched registration is rejected and no token is exchanged', async () => {
  let calls = 0;
  const flow = await beginChatGptAuthorization({ hostId, clientId, onRegistration: async () => {},
    fetch: async () => { calls++; throw Error('unexpected'); } });
  const auth = new URL(flow.authorizeUrl);
  const callback = new URL(auth.searchParams.get('redirect_uri'));
  callback.searchParams.set('state', auth.searchParams.get('state'));
  callback.searchParams.set('code', 'test-code');
  callback.searchParams.set('client_id', 'oaiapp_other');
  const rejected = assert.rejects(flow.result, /declined or incomplete/);
  assert.equal((await fetch(callback)).status, 400);
  await rejected;
  assert.equal(calls, 0);
});

test('cancelling during token exchange aborts the in-flight request', async () => {
  let signal, startedResolve;
  const started = new Promise(resolve => { startedResolve = resolve; });
  const flow = await beginChatGptAuthorization({ hostId, clientId, onRegistration: async () => {},
    fetch: async (_url, opts) => new Promise((_resolve, reject) => {
      signal = opts.signal;
      signal.addEventListener('abort', () => reject(Error('aborted')), { once: true });
      startedResolve();
    }) });
  const auth = new URL(flow.authorizeUrl);
  const callback = new URL(auth.searchParams.get('redirect_uri'));
  callback.searchParams.set('state', auth.searchParams.get('state'));
  callback.searchParams.set('code', 'test-code');
  const rejected = assert.rejects(flow.result, /cancelled/);
  assert.equal((await fetch(callback)).status, 200);
  await started;
  flow.cancel();
  await rejected;
  assert.equal(signal.aborted, true);
});
