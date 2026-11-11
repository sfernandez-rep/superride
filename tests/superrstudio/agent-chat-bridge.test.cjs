const test = require('node:test');
const assert = require('node:assert/strict');
const { ChatBridge } = require('../../src/node/desktop/src/main/superr-agent/chat-bridge');

test('bridge reports actual account state and refuses turns without isolation', async () => {
  let connected = false, opened = '';
  const accounts = {
    list: async () => connected ? [{ state: 'connected' }] : [],
    beginSignIn: async () => ({ authorizeUrl: 'https://auth.openai.com/test',
      result: Promise.resolve().then(() => { connected = true; }), cancel: () => {} }),
  };
  const bridge = new ChatBridge(async () => accounts, async url => { opened = url; }, { searchPath: '' });
  assert.deepEqual(await bridge.status('codex'), {provider:'codex', installed:false, authentication:'signed_out', readOnlyAvailable:false, chatAvailable:false});
  assert.equal((await bridge.status('gemini')).authentication, 'unknown');
  await assert.rejects(bridge.send('codex', 'hello'), /isolation/);
  await assert.rejects(bridge.status('gemini-api'), /credential storage is unavailable/);
  await assert.rejects(bridge.send('codex', ''), /Invalid message/);
  await assert.rejects(bridge.cancel('codex'), /No active/);
  await assert.rejects(bridge.signIn('gemini'), /not offered/);
  await assert.rejects(bridge.status('bogus'), /Invalid provider/);
  assert.equal((await bridge.signIn('codex')).authentication, 'connected');
  assert.equal(opened, 'https://auth.openai.com/test');
  bridge.shutdown();
  await assert.rejects(bridge.status('codex'), /closed/);
});

test('a browser failure cancels the authentication attempt', async () => {
  let cancelled = false;
  const accounts = { beginSignIn: async () => ({authorizeUrl:'https://auth.openai.com/test',
    result: Promise.resolve(), cancel: () => { cancelled = true; }}) };
  const bridge = new ChatBridge(async () => accounts, async () => {throw Error('browser error');}, { searchPath: '' });
  await assert.rejects(bridge.signIn('codex'), /authorization page/);
  assert.equal(cancelled, true);
});

test('a second sign-in cannot race an active attempt', async () => {
  let finish;
  const accounts = { list: async () => [], beginSignIn: async () => ({
    authorizeUrl:'https://auth.openai.com/test', result:new Promise(resolve => { finish = resolve; }), cancel: () => {},
  }) };
  const bridge = new ChatBridge(async () => accounts, async () => {}, { searchPath: '' });
  const first = bridge.signIn('codex');
  await assert.rejects(bridge.signIn('codex'), /already running/);
  while (!finish) await new Promise(resolve => setImmediate(resolve));
  finish();
  await first;
});
