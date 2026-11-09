// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
// Bidirectional newline-delimited JSON-RPC transport. No credentials are logged.
import { ChildProcessWithoutNullStreams, spawn } from 'node:child_process';
import { StringDecoder } from 'node:string_decoder';

type RpcId = string | number;
type ObjectValue = Record<string, unknown>;
type Pending = { resolve: (value: unknown) => void; reject: (error: Error) => void; timer?: NodeJS.Timeout };
type RequestHandler = (method: string, params: unknown) => Promise<unknown>;
type NotificationHandler = (method: string, params: unknown) => void;

export class AgentRpcError extends Error {
  constructor(readonly code: number, readonly reason?: string) {
    super(reason ? `Agent request failed: ${reason}` : `Agent request failed (${code})`);
    this.name = 'AgentRpcError';
  }
}
const SAFE_REASONS = new Set(['subscription_sharing_user_not_eligible',
  'subscription_sharing_usage_limit_exceeded', 'subscription_sharing_usage_unavailable',
  'auth_required']);
function safeReason(value: unknown, depth = 0): string | undefined {
  if (typeof value === 'string') return SAFE_REASONS.has(value) ? value : undefined;
  if (!object(value) || depth >= 4) return undefined;
  for (const key of ['code', 'type', 'error', 'data']) {
    const found = safeReason(value[key], depth + 1);
    if (found) return found;
  }
  return undefined;
}

const MAX_BUFFER = 4 * 1024 * 1024;
const MAX_PENDING = 128;

function object(value: unknown): value is ObjectValue {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export class JsonRpcProcess {
  private readonly child: ChildProcessWithoutNullStreams;
  private readonly decoder = new StringDecoder('utf8');
  private readonly pending = new Map<RpcId, Pending>();
  private nextId = 0;
  private buffer = '';
  private closed = false;

  constructor(executable: string, args: readonly string[], cwd: string,
    private readonly onRequest: RequestHandler,
    private readonly onNotification: NotificationHandler,
    onExit: (code: number | null) => void,
    private readonly wire: 'acp' | 'codex' = 'acp', env?: NodeJS.ProcessEnv) {
    // No shell or command string: executable and arguments remain distinct.
    this.child = spawn(executable, [...args], { cwd, shell: false, windowsHide: true,
      stdio: ['pipe', 'pipe', 'pipe'], env });
    this.child.stdout.on('data', (bytes: Buffer) => this.receive(bytes));
    // Stderr can contain credentials or private project text; drain, never persist it.
    this.child.stderr.resume();
    this.child.on('error', () => this.fail('Agent process could not start'));
    this.child.stdin.on('error', () => this.fail('Agent input closed'));
    this.child.on('close', code => { this.fail('Agent process exited'); onExit(code); });
  }

  request(method: string, params: unknown, timeoutMs = 30000): Promise<unknown> {
    if (this.closed) return Promise.reject(new Error('Agent connection is closed'));
    if (this.pending.size >= MAX_PENDING) return Promise.reject(new Error('Too many pending requests'));
    const id = ++this.nextId;
    return new Promise((resolve, reject) => {
      const timer = timeoutMs > 0 ? setTimeout(() => this.fail('Agent request timed out'), timeoutMs) : undefined;
      timer?.unref();
      this.pending.set(id, { resolve, reject, timer });
      try { this.send({ jsonrpc: '2.0', id, method, params }); }
      catch (error) { if (timer) clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }

  notify(method: string, params: unknown): void {
    this.send({ jsonrpc: '2.0', method, params });
  }

  shutdown(): void {
    if (this.closed) return;
    this.fail('Agent connection closed');
  }

  private send(message: ObjectValue): void {
    if (this.closed) throw new Error('Agent connection is closed');
    if (this.wire === 'codex') delete message.jsonrpc;
    const line = JSON.stringify(message) + '\n';
    if (Buffer.byteLength(line, 'utf8') > MAX_BUFFER) throw new Error('Agent message too large');
    this.child.stdin.write(line);
  }

  private receive(bytes: Buffer): void {
    if (this.closed) return;
    this.buffer += this.decoder.write(bytes);
    let end: number;
    while ((end = this.buffer.indexOf('\n')) >= 0) {
      const line = this.buffer.slice(0, end).replace(/\r$/, '');
      this.buffer = this.buffer.slice(end + 1);
      if (Buffer.byteLength(line, 'utf8') > MAX_BUFFER) { this.fail('Agent output exceeded limit'); return; }
      if (!line) continue;
      let message: unknown;
      try { message = JSON.parse(line); } catch { this.fail('Invalid agent response'); return; }
      if (!object(message) || (this.wire === 'acp' && message.jsonrpc !== '2.0') ||
          (this.wire === 'codex' && message.jsonrpc !== undefined && message.jsonrpc !== '2.0')) {
        this.fail('Invalid agent response'); return;
      }
      this.dispatch(message);
      if (this.closed) return;
    }
    if (Buffer.byteLength(this.buffer, 'utf8') > MAX_BUFFER) this.fail('Agent output exceeded limit');
  }

  private dispatch(message: ObjectValue): void {
    const id = message.id;
    if (typeof message.method === 'string') {
      if (id === undefined) {
        try { this.onNotification(message.method, message.params); }
        catch { this.fail('Agent notification handler failed'); }
      } else if (typeof id === 'string' || typeof id === 'number') {
        const method = message.method;
        void Promise.resolve().then(() => this.onRequest(method, message.params)).then(
          result => { if (!this.closed) this.send({ jsonrpc: '2.0', id, result }); },
          () => { if (!this.closed) this.send({ jsonrpc: '2.0', id, error: { code: -32601, message: 'Request not supported' } }); },
        ).catch(() => this.fail('Unable to reply to agent'));
      } else this.fail('Invalid agent request identifier');
      return;
    }
    if (typeof id !== 'string' && typeof id !== 'number') { this.fail('Invalid agent response identifier'); return; }
    const pending = this.pending.get(id);
    if (!pending) return; // A late response can arrive after cancellation or shutdown.
    this.pending.delete(id);
    if (pending.timer) clearTimeout(pending.timer);
    if ('error' in message) {
      // Preserve the provider error code, but do not copy potentially sensitive server data into logs.
      const code = object(message.error) && typeof message.error.code === 'number' ? message.error.code : 0;
      pending.reject(new AgentRpcError(code, safeReason(message.error)));
    } else if ('result' in message) pending.resolve(message.result);
    else pending.reject(new Error('Agent response has no result'));
  }

  private fail(message: string): void {
    if (this.closed) return;
    this.closed = true;
    for (const pending of this.pending.values()) {
      if (pending.timer) clearTimeout(pending.timer);
      pending.reject(new Error(message));
    }
    this.pending.clear();
    this.child.stdin.destroy();
    if (this.child.exitCode === null && this.child.signalCode === null) this.child.kill();
  }
}
