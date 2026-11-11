// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import { isAbsolute, resolve } from 'node:path';
import { JsonRpcProcess } from './json-rpc-process';
import { childEnvironment } from './child-environment';

type Obj = Record<string, unknown>;
type Rpc = Pick<JsonRpcProcess, 'request' | 'notify' | 'shutdown'>;
type RpcFactory = (executable: string, args: readonly string[], cwd: string,
  onRequest: (method: string, params: unknown) => Promise<unknown>,
  onNotification: (method: string, params: unknown) => void,
  onExit: (code: number | null) => void, env: NodeJS.ProcessEnv) => Rpc;
function obj(value: unknown): value is Obj {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * ACP protocol client. It does not claim to sandbox an agent's own tools.
 * A caller must independently enforce the project access policy before exposing it.
 */
export class AcpClient {
  private readonly rpc: Rpc;
  private initialized = false;
  private sessions = new Set<string>();
  private readonly activeTurns = new Set<string>();
  private readonly cancelTimers = new Map<string, NodeJS.Timeout>();
  private authenticationMethods = new Set<string>();
  private canLoadSession = false;
  private readonly workspace: string;

  constructor(executable: string, cwd: string, privateGeminiDir: string,
    onUpdate: (params: unknown) => void, onExit: (code: number | null) => void,
    factory: RpcFactory = (exe, args, dir, request, notification, exit, env) =>
      new JsonRpcProcess(exe, args, dir, request, notification, exit, 'acp', env)) {
    if (!isAbsolute(executable) || !isAbsolute(cwd) || !isAbsolute(privateGeminiDir))
      throw new Error('Absolute executable, workspace and private agent paths are required');
    this.workspace = resolve(cwd);
    // Antigravity's inherited permission rules can preapprove actions, even
    // with this flag. Do not connect this client to a product UI until those
    // rules and filesystem isolation are enforced independently.
    this.rpc = factory(executable, ['acp', '--sandbox', '--disable-telemetry', '--gemini-dir', privateGeminiDir,
      '--include-default-customizations=false'], cwd,
      async (method, params) => {
        if (method === 'session/request_permission') {
          if (obj(params) && Array.isArray(params.options)) {
            const reject = params.options.find((option: unknown) => obj(option) && option.kind === 'reject_once' && typeof option.optionId === 'string');
            if (obj(reject)) return { outcome: { outcome: 'selected', optionId: reject.optionId } };
          }
          return { outcome: { outcome: 'cancelled' } };
        }
        throw new Error('Unsupported client operation');
      },
      (method, params) => { if (method === 'session/update') onUpdate(params); }, code => {
        this.initialized = false; this.sessions.clear(); this.activeTurns.clear(); onExit(code);
      },
      childEnvironment(process.env));
  }

  async initialize(): Promise<Obj> {
    const result = await this.rpc.request('initialize', {
      protocolVersion: 1,
      clientInfo: { name: 'superr', title: 'SuperR', version: '0.1.1' },
      clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false },
    });
    if (!obj(result) || result.protocolVersion !== 1) { this.shutdown(); throw new Error('Unsupported ACP protocol version'); }
    this.authenticationMethods.clear();
    if (Array.isArray(result.authMethods))
      for (const method of result.authMethods)
        if (obj(method) && typeof method.id === 'string' && (method.type === undefined || method.type === 'agent'))
          this.authenticationMethods.add(method.id);
    this.canLoadSession = obj(result.agentCapabilities) && result.agentCapabilities.loadSession === true;
    this.initialized = true;
    return result;
  }

  async authenticate(methodId: string): Promise<void> {
    this.requireInitialized();
    if (methodId !== 'oauth-personal' || !this.authenticationMethods.has(methodId))
      throw new Error('Unsupported authentication method');
    await this.rpc.request('authenticate', { methodId });
  }

  async createSession(cwd: string): Promise<Obj> {
    this.requireInitialized();
    this.requireWorkspace(cwd);
    const result = await this.rpc.request('session/new', { cwd, mcpServers: [] });
    if (!obj(result) || typeof result.sessionId !== 'string' || !result.sessionId)
      throw new Error('Agent returned an invalid session');
    this.sessions.add(result.sessionId);
    return result;
  }

  async loadSession(sessionId: string, cwd: string): Promise<Obj> {
    this.requireInitialized();
    if (!this.canLoadSession) throw new Error('Agent does not support resuming sessions');
    if (!sessionId) throw new Error('A session ID is required');
    this.requireWorkspace(cwd);
    const result = await this.rpc.request('session/load', { sessionId, cwd, mcpServers: [] });
    if (!obj(result)) throw new Error('Agent returned an invalid session');
    this.sessions.add(sessionId);
    return result;
  }

  async prompt(sessionId: string, text: string): Promise<unknown> {
    this.requireSession(sessionId);
    if (!text.trim()) throw new Error('A message is required');
    if (this.activeTurns.has(sessionId)) throw new Error('A turn is already running');
    this.activeTurns.add(sessionId);
    try { return await this.rpc.request('session/prompt', { sessionId, prompt: [{ type: 'text', text }] }, 0); }
    finally {
      this.activeTurns.delete(sessionId);
      const timer = this.cancelTimers.get(sessionId);
      if (timer) clearTimeout(timer);
      this.cancelTimers.delete(sessionId);
    }
  }

  cancel(sessionId: string): void {
    this.requireSession(sessionId);
    if (!this.activeTurns.has(sessionId)) throw new Error('No active turn');
    this.rpc.notify('session/cancel', { sessionId });
    if (!this.cancelTimers.has(sessionId)) {
      const timer = setTimeout(() => this.shutdown(), 5000);
      timer.unref();
      this.cancelTimers.set(sessionId, timer);
    }
  }

  shutdown(): void {
    this.initialized = false;
    this.sessions.clear();
    this.activeTurns.clear();
    for (const timer of this.cancelTimers.values()) clearTimeout(timer);
    this.cancelTimers.clear();
    this.authenticationMethods.clear();
    this.canLoadSession = false;
    this.rpc.shutdown();
  }

  private requireInitialized(): void {
    if (!this.initialized) throw new Error('Agent connection is not initialized');
  }
  private requireSession(id: string): void {
    this.requireInitialized();
    if (!this.sessions.has(id)) throw new Error('Unknown agent session');
  }
  private requireWorkspace(cwd: string): void {
    if (!isAbsolute(cwd) || resolve(cwd) !== this.workspace) throw new Error('Workspace does not match the authorized directory');
  }
}
