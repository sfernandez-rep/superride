// Disposable test agent; no network access or real credentials.
const readline = require('node:readline');
const input = readline.createInterface({ input: process.stdin });
let pendingPrompt;
function send(value) {
  const bytes = Buffer.from(JSON.stringify(value) + '\n');
  // Deliberately split UTF-8 across writes to exercise stream framing.
  const split = Math.max(1, bytes.indexOf(Buffer.from('á')) + 1);
  process.stdout.write(bytes.subarray(0, split));
  process.stdout.write(bytes.subarray(split));
}
input.on('line', line => {
  const msg = JSON.parse(line);
  if (msg.method === 'initialize') send({ jsonrpc: '2.0', id: msg.id, result: { protocolVersion: 1, agentCapabilities: { loadSession: true } } });
  else if (msg.method === 'authenticate') send({ jsonrpc: '2.0', id: msg.id, result: {} });
  else if (msg.method === 'session/new') send({ jsonrpc: '2.0', id: msg.id, result: { sessionId: 's1' } });
  else if (msg.method === 'session/load') send({ jsonrpc: '2.0', id: msg.id, result: {} });
  else if (msg.method === 'session/prompt') {
    pendingPrompt = msg.id;
    send({ jsonrpc: '2.0', method: 'session/update', params: { sessionId: 's1', update: { sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'hola á' } } } });
    send({ jsonrpc: '2.0', id: 'permission-1', method: 'session/request_permission', params: { sessionId: 's1', options: [{ kind: 'allow_once', optionId: 'yes' }] } });
  } else if (msg.id === 'permission-1') {
    send({ jsonrpc: '2.0', method: 'session/update', params: { sessionId: 's1', update: { sessionUpdate: 'permission-test', outcome: msg.result.outcome.outcome } } });
  } else if (msg.method === 'session/cancel' && pendingPrompt) {
    send({ jsonrpc: '2.0', id: pendingPrompt, result: { stopReason: 'cancelled' } });
    pendingPrompt = null;
  } else if (msg.method === 'broken') process.stdout.write('{not json}\n');
  else if (msg.method === 'hang') { /* The test closes the process. */ }
});
