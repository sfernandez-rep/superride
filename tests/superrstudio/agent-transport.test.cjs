// Tests use a real child process implementing a small fake ACP peer.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { JsonRpcProcess } = require('../../src/node/desktop/src/main/superr-agent/json-rpc-process');
const { AcpClient } = require('../../src/node/desktop/src/main/superr-agent/acp-client');
const { CodexClient } = require('../../src/node/desktop/src/main/superr-agent/codex-client');
const fixture = path.join(__dirname, 'fixtures/fake-acp.cjs');
const codexFixture = path.join(__dirname, 'fixtures/fake-codex.cjs');
const cwd = __dirname;
const sleepUntil = async condition => {
  const until = Date.now() + 5000;
  while (!condition() && Date.now() < until) await new Promise(resolve => setTimeout(resolve, 10));
  assert.ok(condition(), 'timed out waiting for event');
};

test('ACP handshake, sessions, streaming, denied permission and cancellation', async () => {
  const updates = [];
  let launched;
  const client = new AcpClient(process.execPath, cwd, x => updates.push(x), () => {},
    (exe, args, dir, request, notification, exit, env) => {
      launched = { exe, args, dir, leakedApiKey: Object.hasOwn(env, 'OPENAI_API_KEY') };
      return new JsonRpcProcess(process.execPath, [fixture], dir, request, notification, exit, 'acp', env);
    });
  try {
    assert.deepEqual(launched.args, ['acp', '--sandbox', '--disable-telemetry']);
    assert.equal(launched.leakedApiKey, false);
    await assert.rejects(client.prompt('s1', 'hi'), /not initialized/);
    const capabilities = await client.initialize();
    assert.equal(capabilities.protocolVersion, 1);
    await assert.rejects(client.authenticate('unknown'), /Unsupported/);
    await client.authenticate('oauth-personal');
    await assert.rejects(client.createSession(path.dirname(cwd)), /Workspace/);
    assert.equal((await client.createSession(cwd)).sessionId, 's1');
    await client.loadSession('s2', cwd);
    const turn = client.prompt('s1', 'Analyze the project');
    await assert.rejects(client.prompt('s1', 'another'), /already running/);
    await sleepUntil(() => updates.length === 2);
    assert.equal(updates[0].update.content.text, 'hola á');
    assert.equal(updates[1].update.outcome, 'no');
    client.cancel('s1');
    assert.equal((await turn).stopReason, 'cancelled');
    assert.throws(() => client.cancel('unrecognized'), /Unknown/);
  } finally { client.shutdown(); }
});

test('malformed protocol terminates the connection and rejects pending requests', async () => {
  const rpc = new JsonRpcProcess(process.execPath, [fixture], cwd, async () => ({}), () => {}, () => {});
  const pending = rpc.request('hang', {});
  const broken = rpc.request('broken', {});
  await Promise.all([assert.rejects(pending, /Invalid agent response/), assert.rejects(broken, /Invalid agent response/)]);
  await assert.rejects(rpc.request('anything', {}), /closed/);
});

test('shutdown rejects outstanding work', async () => {
  const rpc = new JsonRpcProcess(process.execPath, [fixture], cwd, async () => ({}), () => {}, () => {});
  const pending = rpc.request('hang', {});
  rpc.shutdown();
  await assert.rejects(pending, /closed/);
});

test('an unresponsive agent request times out and closes the process', async () => {
  const rpc = new JsonRpcProcess(process.execPath, [fixture], cwd, async () => ({}), () => {}, () => {});
  await assert.rejects(rpc.request('hang', {}, 60), /timed out/);
  await assert.rejects(rpc.request('anything', {}), /closed/);
});

test('provider errors preserve only approved structured reason codes', async () => {
  const rpc = new JsonRpcProcess(process.execPath, [codexFixture], cwd, async () => ({}), () => {}, () => {}, 'codex');
  try {
    await rpc.request('initialize', {});
    rpc.notify('initialized', {});
    await assert.rejects(rpc.request('mock-error', {}), error => {
      assert.equal(error.code, -32000);
      assert.equal(error.reason, 'subscription_sharing_user_not_eligible');
      assert.doesNotMatch(error.message, /PRIVATE/);
      return true;
    });
  } finally { rpc.shutdown(); }
});

test('Codex app-server handshake, scoped thread, streaming and denied writes', async () => {
  const updates = [];
  let launch;
  const client = new CodexClient(process.execPath, cwd, cwd, 'test-token',
    (method, params) => updates.push({ method, params }), () => {},
    (exe, args, dir, request, notification, exit, wire, env) => {
      launch = { args, wire, hasToken: env.ACCESS_TOKEN === 'test-token', home: env.CODEX_HOME };
      return new JsonRpcProcess(process.execPath, [codexFixture], dir, request, notification, exit, wire, env);
    });
  try {
    assert.equal(launch.wire, 'codex');
    assert.equal(launch.hasToken, true);
    assert.equal(launch.home, cwd);
    assert.ok(launch.args.includes('model_providers.openai_chatgpt_plan.base_url="https://api.openai.com/v1"'));
    assert.ok(launch.args.includes('shell_environment_policy.filters.ACCESS_TOKEN="exclude"'));
    await client.initialize();
    assert.deepEqual(await client.models(), { data: [] });
    await assert.rejects(client.startThread(path.dirname(cwd)), /Workspace/);
    assert.equal((await client.startThread(cwd)).thread.id, 't1');
    assert.equal((await client.resumeThread('t2', cwd)).thread.id, 't2');
    assert.equal((await client.prompt('t1', 'Explain the code')).turn.id, 'turn1');
    await assert.rejects(client.prompt('t1', 'another'), /already running/);
    await sleepUntil(() => updates.length === 2);
    assert.equal(updates[0].params.delta, 'hola á');
    assert.equal(updates[1].params.decision, 'decline');
    await client.cancel('t1', 'turn1');
    await assert.rejects(client.prompt('other', 'test'), /Unknown/);
  } finally { client.shutdown(); }
});
