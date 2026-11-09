const test = require('node:test');
const assert = require('node:assert/strict');
const { AntigravityProvider, CodexProvider } = require('../../src/node/desktop/src/main/superr-agent/agent-provider');

function deferred() {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
}

test('ACP provider maps actual completion and cancellation outcomes', async () => {
  let stopped = false;
  const client = {
    initialize: async () => ({ protocolVersion: 1 }),
    createSession: async () => ({ sessionId: 'session' }),
    loadSession: async () => {}, prompt: async (_, text) => ({ stopReason: text }),
    cancel: () => { stopped = true; }, shutdown: () => {},
  };
  const provider = new AntigravityProvider(client);
  assert.equal((await provider.connect()).protocolVersion, 1);
  assert.equal(await provider.createSession('/project'), 'session');
  assert.deepEqual(await provider.sendMessage('session', 'end_turn'), { status: 'completed' });
  assert.deepEqual(await provider.sendMessage('session', 'cancelled'), { status: 'cancelled' });
  assert.deepEqual(await provider.sendMessage('session', 'max_tokens'), { status: 'incomplete' });
  await provider.cancelRequest('session');
  assert.equal(stopped, true);
});

test('Codex provider handles completion before start response and delayed cancellation', async () => {
  const start = deferred();
  const cancelled = [];
  const client = { prompt: () => start.promise, cancel: async (...args) => cancelled.push(args), shutdown: () => {} };
  const provider = new CodexProvider(client);
  const turn = provider.sendMessage('thread', 'hello');
  await assert.rejects(provider.sendMessage('thread', 'again'), /already running/);
  await provider.cancelRequest('thread');
  start.resolve({ turn: { id: 'turn' } });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(cancelled, [['thread', 'turn']]);
  provider.onNotification('turn/completed', { threadId: 'thread', turn: { id: 'turn', status: 'interrupted' } });
  assert.deepEqual(await turn, { status: 'cancelled' });

  const next = deferred();
  client.prompt = () => next.promise;
  const earlyTurn = provider.sendMessage('thread', 'hello');
  provider.onNotification('turn/completed', { threadId: 'thread', turn: { id: 'early', status: 'completed' } });
  next.resolve({ turn: { id: 'early' } });
  assert.deepEqual(await earlyTurn, { status: 'completed' });
});

test('Codex provider rejects active work on exit and ignores unrelated notifications', async () => {
  const start = deferred();
  const provider = new CodexProvider({ prompt: () => start.promise, shutdown: () => {} });
  const turn = provider.sendMessage('thread', 'hello');
  provider.onNotification('turn/completed', { threadId: 'other', turn: { id: 'turn', status: 'completed' } });
  provider.onExit();
  await assert.rejects(turn, /exited/);
  start.resolve({ turn: { id: 'turn' } });
  await assert.rejects(provider.cancelRequest('thread'), /No active turn/);
});
