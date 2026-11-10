// Gemini API client, encrypted key storage and the Chat IA bridge's Gemini mode.
// Every response here is simulated (fake fetch); no Google service is contacted.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { GeminiApi, classifyError } = require('../../src/node/desktop/src/main/superr-agent/gemini-api');
const { CredentialVault } = require('../../src/node/desktop/src/main/superr-agent/credential-vault');
const { ChatBridge } = require('../../src/node/desktop/src/main/superr-agent/chat-bridge');

const KEY = 'AIzaSyTEST-not-a-real-key_123';
const codecKey = crypto.randomBytes(32);
const codec = {
  encrypt(text) { const iv = crypto.randomBytes(12), cipher = crypto.createCipheriv('aes-256-gcm', codecKey, iv);
    const body = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), body]); },
  decrypt(bytes) { const cipher = crypto.createDecipheriv('aes-256-gcm', codecKey, bytes.subarray(0, 12));
    cipher.setAuthTag(bytes.subarray(12, 28)); return Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString('utf8'); },
};

function sse(chunks, split = 7) {
  const text = chunks.map(c => `data: ${JSON.stringify(c)}\r\n\r\n`).join('');
  const bytes = Buffer.from(text, 'utf8');
  return new ReadableStream({ start(controller) {
    for (let i = 0; i < bytes.length; i += split) controller.enqueue(new Uint8Array(bytes.subarray(i, i + split)));
    controller.close();
  } });
}
const models = { models: [
  { name: 'models/gemini-3.6-flash', supportedGenerationMethods: ['generateContent', 'countTokens'] },
  { name: 'models/gemini-4-argon', supportedGenerationMethods: ['generateContent'] },
  { name: 'models/gemini-embedding-2', supportedGenerationMethods: ['embedContent'] },
] };
const answer = [
  { candidates: [{ content: { role: 'model', parts: [{ text: 'mean() calcula ' }] } }] },
  { candidates: [{ content: { role: 'model', parts: [{ text: 'thinking', thought: true }, { text: 'la media aritmética.' }] } }] },
  { candidates: [{ content: { role: 'model', parts: [{ text: '' }] }, finishReason: 'STOP' }], usageMetadata: { totalTokenCount: 9 } },
];

function fakeFetch(handler) {
  const calls = [];
  const fetch = async (url, init) => { calls.push({ url, init }); return handler(url, init, calls.length); };
  return { fetch, calls };
}
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const googleError = (code, status, message, reason) => ({ error: { code, status, message,
  ...(reason ? { details: [{ '@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason }] } : {}) } });

test('streams text in order, skips thoughts and keeps the key out of the URL', async () => {
  const { fetch, calls } = fakeFetch(() => new Response(sse(answer), { status: 200 }));
  const api = new GeminiApi(fetch);
  const parts = [];
  const result = await api.stream(KEY, 'gemini-3.6-flash', [{ role: 'user', text: 'Hola' }], t => parts.push(t),
    new AbortController().signal);
  assert.deepEqual(result, { status: 'completed', finishReason: 'STOP' });
  assert.equal(parts.join(''), 'mean() calcula la media aritmética.');
  assert.equal(calls[0].url, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:streamGenerateContent?alt=sse');
  assert.equal(calls[0].init.headers['x-goog-api-key'], KEY);
  assert.equal(calls[0].init.redirect, 'error');
  assert.deepEqual(JSON.parse(calls[0].init.body), { contents: [{ role: 'user', parts: [{ text: 'Hola' }] }] });
  assert.equal(calls[0].url.includes(KEY), false);
});

test('lists only free-tier text models that the key can see', async () => {
  const { fetch, calls } = fakeFetch((url, init, n) => json(200, n === 1 ? { ...models, nextPageToken: 'p2' } :
    { models: [{ name: 'models/gemini-3.5-flash-lite', supportedGenerationMethods: ['generateContent'] }] }));
  const list = await new GeminiApi(fetch).models(KEY);
  assert.deepEqual(list.map(m => m.id), ['gemini-3.6-flash', 'gemini-3.5-flash-lite']);
  assert.match(calls[1].url, /pageToken=p2$/);
});

test('maps invalid keys, quota, verification, region, model, overload and connection failures', async () => {
  const cases = [
    [400, googleError(400, 'INVALID_ARGUMENT', 'API key not valid. Please pass a valid API key.', 'API_KEY_INVALID'), 'invalid_key'],
    [429, googleError(429, 'RESOURCE_EXHAUSTED', 'You exceeded your current quota.'), 'quota'],
    [403, googleError(403, 'PERMISSION_DENIED', 'Verify.', 'FREE_TIER_VERIFICATION_REQUIRED'), 'verification'],
    [400, googleError(400, 'FAILED_PRECONDITION', 'User location is not supported for the API use.'), 'region'],
    [404, googleError(404, 'NOT_FOUND', 'models/x is not found'), 'model'],
    [403, googleError(403, 'PERMISSION_DENIED', 'Your project has been denied access.'), 'permission'],
    [503, googleError(503, 'UNAVAILABLE', 'The model is overloaded.'), 'unavailable'],
    [402, { error: { code: 'payment_required', message: 'Prepay balance depleted' } }, 'billing'],
  ];
  for (const [status, body, kind] of cases) {
    const { fetch } = fakeFetch(() => json(status, body));
    await assert.rejects(new GeminiApi(fetch).models(KEY), e => e.kind === kind && !e.message.includes(KEY), kind);
  }
  const offline = new GeminiApi(async () => { throw new TypeError('fetch failed'); });
  await assert.rejects(offline.models(KEY), e => e.kind === 'connection');
  assert.equal(classifyError(500, 'not json').kind, 'unavailable');
});

test('reports blocked prompts and errors inside the stream, and stops on cancel', async () => {
  const blocked = new GeminiApi(async () => new Response(sse([{ promptFeedback: { blockReason: 'SAFETY' } }])));
  await assert.rejects(blocked.stream(KEY, 'gemini-3.6-flash', [{ role: 'user', text: 'x' }], () => {}, new AbortController().signal),
    e => e.kind === 'blocked');
  const midstream = new GeminiApi(async () => new Response(sse([answer[0], googleError(429, 'RESOURCE_EXHAUSTED', 'quota')])));
  await assert.rejects(midstream.stream(KEY, 'gemini-3.6-flash', [{ role: 'user', text: 'x' }], () => {}, new AbortController().signal),
    e => e.kind === 'quota');
  const controller = new AbortController();
  const slow = new GeminiApi(async (url, init) => new Response(new ReadableStream({ start(c) {
    c.enqueue(new TextEncoder().encode(`data: ${JSON.stringify(answer[0])}\n\n`));
    init.signal.addEventListener('abort', () => c.error(new DOMException('aborted', 'AbortError')));
  } })));
  const parts = [];
  const pending = slow.stream(KEY, 'gemini-3.6-flash', [{ role: 'user', text: 'x' }], t => { parts.push(t); controller.abort(); },
    controller.signal);
  assert.deepEqual(await pending, { status: 'cancelled' });
  assert.equal(parts.length, 1);
  await assert.rejects(new GeminiApi(fetch).stream(KEY, '../x', [{ role: 'user', text: 'x' }], () => {}, controller.signal),
    e => e.kind === 'model');
});

test('the vault stores the key encrypted and rejects malformed secrets', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-gemini-'));
  try {
    const vault = await CredentialVault.open(root, codec);
    const id = 'c'.repeat(32);
    assert.equal(await vault.loadSecret(id), null);
    await vault.saveSecret(id, KEY);
    assert.equal(await vault.loadSecret(id), KEY);
    assert.equal((await fs.readFile(path.join(root, `${id}.bin`))).includes(Buffer.from('AIza')), false);
    await assert.rejects(vault.saveSecret(id, 'has space'), /Invalid secret/);
    await assert.rejects(vault.load(id), /Cannot decrypt or validate/);
    await vault.remove(id);
    assert.equal(await vault.loadSecret(id), null);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});

test('bridge: key check before storing, streamed turns with history, cancel, and no key returned', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-bridge-'));
  let opened = '';
  const events = [];
  const { fetch, calls } = fakeFetch((url, init) => {
    if (url.includes('/models?')) return init.headers['x-goog-api-key'] === KEY ? json(200, models) :
      json(400, googleError(400, 'INVALID_ARGUMENT', 'API key not valid.', 'API_KEY_INVALID'));
    return new Response(sse(answer));
  });
  try {
    const vault = await CredentialVault.open(root, codec);
    const bridge = new ChatBridge(async () => { throw new Error('no accounts'); }, async url => { opened = url; },
      { searchPath: '', secrets: async () => vault, gemini: new GeminiApi(fetch), onEvent: e => events.push(e) });
    assert.deepEqual(await bridge.status('gemini-api'), { provider: 'gemini-api', installed: true,
      authentication: 'signed_out', readOnlyAvailable: false, chatAvailable: false });
    assert.deepEqual(await bridge.send('gemini-api', 'Hola', 'gemini-3.6-flash', 't1'), { status: 'error', kind: 'no_key' });
    await bridge.openKeyPage('gemini-api');
    assert.equal(opened, 'https://aistudio.google.com/apikey');
    assert.deepEqual(await bridge.setKey('gemini-api', 'AIzaWRONGKEY-1234'), { ok: false, kind: 'invalid_key' });
    assert.equal((await bridge.status('gemini-api')).authentication, 'signed_out');
    assert.deepEqual(await bridge.setKey('gemini-api', ` ${KEY} `), { ok: true, models: [{ id: 'gemini-3.6-flash', label: 'Gemini 3.6 Flash' }] });
    const status = await bridge.status('gemini-api');
    assert.equal(status.chatAvailable, true);
    assert.equal(JSON.stringify(status).includes(KEY), false);
    await assert.rejects(bridge.send('gemini-api', 'Hola', 'gemini-4-argon', 't1'), /Invalid model/);
    await assert.rejects(bridge.send('gemini-api', 'Hola', 'gemini-3.6-flash', 'bad turn'), /Invalid turn/);
    assert.deepEqual(await bridge.send('gemini-api', 'Hola', 'gemini-3.6-flash', 't1'), { status: 'completed', finishReason: 'STOP' });
    assert.equal(events.map(e => e.text).join(''), 'mean() calcula la media aritmética.');
    assert.ok(events.every(e => e.turn === 't1' && e.provider === 'gemini-api'));
    await bridge.send('gemini-api', 'Gracias', 'gemini-3.6-flash', 't2');
    assert.deepEqual(JSON.parse(calls.at(-1).init.body).contents.map(c => c.role), ['user', 'model', 'user']);
    await bridge.newChat('gemini-api');
    await bridge.send('gemini-api', 'Otra', 'gemini-3.6-flash', 't3');
    assert.equal(JSON.parse(calls.at(-1).init.body).contents.length, 1);
    await assert.rejects(bridge.cancel('gemini-api'), /No active/);
    await assert.rejects(bridge.setKey('gemini', KEY), /Only the Gemini API/);
    await assert.rejects(bridge.send('gemini', 'Hola', 'gemini-3.6-flash', 't4'), /isolation/);
    assert.equal((await bridge.forgetKey('gemini-api')).authentication, 'signed_out');
    assert.equal(await vault.loadSecret(require('node:crypto').createHash('md5').update('superr-gemini-api-key').digest('hex')), null);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});

test('bridge: a second message while streaming is refused and Stop cancels the turn', async () => {
  let release;
  const gemini = new GeminiApi(async (url, init) => new Response(new ReadableStream({ start(c) {
    c.enqueue(new TextEncoder().encode(`data: ${JSON.stringify(answer[0])}\n\n`));
    release = () => c.close();
    init.signal.addEventListener('abort', () => c.error(new DOMException('aborted', 'AbortError')));
  } })));
  const secrets = { loadSecret: async () => KEY, saveSecret: async () => {}, remove: async () => {} };
  const bridge = new ChatBridge(async () => ({}), async () => {}, { secrets: async () => secrets, gemini });
  const first = bridge.send('gemini-api', 'Hola', 'gemini-3.6-flash', 'a');
  while (!release) await new Promise(r => setImmediate(r));
  assert.deepEqual(await bridge.send('gemini-api', 'Otra', 'gemini-3.6-flash', 'b'), { status: 'error', kind: 'busy' });
  await bridge.cancel('gemini-api');
  assert.deepEqual(await first, { status: 'cancelled' });
});

test('a 429 carries only what Google reported: scope, limit and retry delay', async () => {
  const body = { error: { code: 429, status: 'RESOURCE_EXHAUSTED', message: 'You exceeded your current quota.', details: [
    { '@type': 'type.googleapis.com/google.rpc.QuotaFailure', violations: [{
      quotaMetric: 'generativelanguage.googleapis.com/generate_content_free_tier_requests',
      quotaId: 'GenerateRequestsPerDayPerProjectPerModel-FreeTier', quotaValue: '20' }] },
    { '@type': 'type.googleapis.com/google.rpc.RetryInfo', retryDelay: '41.5s' } ] } };
  const error = classifyError(429, body);
  assert.equal(error.kind, 'quota');
  assert.deepEqual(error.quota, { scope: 'day', limit: '20', retryAfterSeconds: 42 });
  assert.deepEqual(classifyError(429, { error: { code: 429 } }).quota, {});
  const perMinute = classifyError(429, { error: { details: [{ '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
    violations: [{ quotaId: 'GenerateRequestsPerMinutePerProjectPerModel-FreeTier', quotaValue: 'lots' }] }] } });
  assert.deepEqual(perMinute.quota, { scope: 'minute' });
  const secrets = { loadSecret: async () => KEY, saveSecret: async () => {}, remove: async () => {} };
  const bridge = new ChatBridge(async () => ({}), async () => {}, { secrets: async () => secrets,
    gemini: new GeminiApi(async () => json(429, body)) });
  assert.deepEqual(await bridge.send('gemini-api', 'Hola', 'gemini-3.6-flash', 'q'),
    { status: 'error', kind: 'quota', quota: { scope: 'day', limit: '20', retryAfterSeconds: 42 } });
});

test('New conversation cancels a running answer and the old exchange is not kept', async () => {
  let release, bodies = [];
  const gemini = new GeminiApi(async (url, init) => { bodies.push(JSON.parse(init.body)); return new Response(new ReadableStream({ start(c) {
    c.enqueue(new TextEncoder().encode(`data: ${JSON.stringify(answer[0])}\n\n`));
    release = () => c.close();
    init.signal.addEventListener('abort', () => c.error(new DOMException('aborted', 'AbortError')));
  } })); });
  const secrets = { loadSecret: async () => KEY, saveSecret: async () => {}, remove: async () => {} };
  const opened = [];
  const bridge = new ChatBridge(async () => ({}), async url => { opened.push(url); }, { secrets: async () => secrets, gemini });
  const first = bridge.send('gemini-api', 'Primera', 'gemini-3.6-flash', 'a');
  while (!release) await new Promise(r => setImmediate(r));
  await bridge.newChat('gemini-api');
  assert.deepEqual(await first, { status: 'cancelled' });
  release = undefined;
  const second = bridge.send('gemini-api', 'Segunda', 'gemini-3.6-flash', 'b');
  while (!release) await new Promise(r => setImmediate(r));
  release();
  await second;
  assert.deepEqual(bodies[1].contents.map(c => c.parts[0].text), ['Segunda']);
  await bridge.openKeyPage('gemini-api', 'limits');
  await bridge.openKeyPage('gemini-api', 'https://evil.example');
  assert.deepEqual(opened, ['https://aistudio.google.com/rate-limit', 'https://aistudio.google.com/apikey']);
});
