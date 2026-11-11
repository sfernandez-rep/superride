// Disposable JSON-RPC-lite mock; no network access or real credentials.
const readline = require('node:readline');
const input = readline.createInterface({ input: process.stdin });
const send = value => process.stdout.write(JSON.stringify(value) + '\n');
let initialized = false;
input.on('line', line => {
  const msg = JSON.parse(line);
  if ('jsonrpc' in msg) throw Error('Codex uses JSON-RPC without a jsonrpc header');
  if (msg.method === 'initialize') send({ id: msg.id, result: { userAgent: 'fake' } });
  else if (msg.method === 'initialized') initialized = true;
  else if (!initialized) throw Error('Missing initialized notification');
  else if (msg.method === 'thread/start' || msg.method === 'thread/resume')
    send({ id: msg.id, result: { thread: { id: msg.params.threadId || 't1' } } });
  else if (msg.method === 'model/list') send({ id: msg.id, result: { data: [] } });
  else if (msg.method === 'mock-error') send({ id: msg.id, error: { code: -32000,
    message: 'DO NOT SHOW PRIVATE TOKEN', data: { type: 'subscription_sharing_user_not_eligible' } } });
  else if (msg.method === 'turn/start') {
    send({ id: msg.id, result: { turn: { id: 'turn1', status: 'inProgress' } } });
    send({ method: 'item/agentMessage/delta', params: { threadId: 't1', delta: 'hola á' } });
    send({ id: 'approve-1', method: 'item/fileChange/requestApproval', params: {} });
  } else if (msg.id === 'approve-1') send({ method: 'approval-result', params: { decision: msg.result.decision } });
  else if (msg.method === 'turn/interrupt') {
    send({ id: msg.id, result: {} });
    send({ method: 'turn/completed', params: { threadId: msg.params.threadId, turn: { id: msg.params.turnId, status: 'interrupted' } } });
  }
});
