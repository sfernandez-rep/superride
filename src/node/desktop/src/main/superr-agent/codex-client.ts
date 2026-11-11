// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import { isAbsolute, resolve } from 'node:path';
import { JsonRpcProcess } from './json-rpc-process';
import { childEnvironment } from './child-environment';

type Obj = Record<string, unknown>;
type Rpc = Pick<JsonRpcProcess, 'request' | 'notify' | 'shutdown'>;
type RpcFactory = (executable: string, args: readonly string[], cwd: string,
  onRequest: (method: string, params: unknown) => Promise<unknown>,
  onNotification: (method: string, params: unknown) => void,
  onExit: (code: number | null) => void, wire: 'codex', env: NodeJS.ProcessEnv) => Rpc;
function obj(value: unknown): value is Obj {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Protocol adapter only. Access tokens must come from SuperR's own verified
 * Sign in with ChatGPT grant, never another application's credential store.
 * The OAuth flow and project isolation are not implemented by this class.
 */
export class CodexClient {
  private readonly rpc: Rpc;
  private initialized = false;
  private threads = new Set<string>();
  private readonly activeTurns = new Map<string, { id?: string; completed: Set<string> }>();
  private readonly workspace: string;

  constructor(executable: string, cwd: string, privateHome: string, accessToken: string,
    onUpdate: (method: string, params: unknown) => void, onExit: (code: number | null) => void,
    factory: RpcFactory = (exe, args, dir, request, notification, exit, wire, env) =>
      new JsonRpcProcess(exe, args, dir, request, notification, exit, wire, env)) {
    if (![executable, cwd, privateHome].every(isAbsolute) || !accessToken)
      throw new Error('Absolute paths and an authorized access token are required');
    this.workspace = resolve(cwd);
    const args = ['app-server', '--listen', 'stdio://',
      '-c', 'model_provider="openai_chatgpt_plan"',
      '-c', 'model_providers.openai_chatgpt_plan.name="ChatGPT plan"',
      '-c', 'model_providers.openai_chatgpt_plan.base_url="https://api.openai.com/v1"',
      '-c', 'model_providers.openai_chatgpt_plan.env_key="ACCESS_TOKEN"',
      '-c', 'model_providers.openai_chatgpt_plan.wire_api="responses"',
      '-c', 'model_providers.openai_chatgpt_plan.requires_openai_auth=false',
      '-c', 'model_providers.openai_chatgpt_plan.supports_websockets=false',
      '-c', 'shell_environment_policy.ignore_default_excludes=false',
      '-c', 'shell_environment_policy.filters.ACCESS_TOKEN="exclude"'];
    const env: NodeJS.ProcessEnv = { ...childEnvironment(process.env), ACCESS_TOKEN: accessToken, CODEX_HOME: privateHome };
    this.rpc = factory(executable, args, cwd, async method => {
      if (method === 'item/commandExecution/requestApproval' || method === 'item/fileChange/requestApproval')
        return { decision: 'decline' };
      throw new Error('Unsupported client operation');
    }, (method, params) => {
      if (method === 'turn/completed' && obj(params) && typeof params.threadId === 'string' &&
          obj(params.turn) && typeof params.turn.id === 'string') {
        const active = this.activeTurns.get(params.threadId);
        if (active && active.id === params.turn.id) this.activeTurns.delete(params.threadId);
        else if (active && !active.id && active.completed.size < 16) active.completed.add(params.turn.id);
      }
      onUpdate(method, params);
    }, code => { this.initialized = false; this.threads.clear(); this.activeTurns.clear(); onExit(code); }, 'codex', env);
  }

  async initialize(): Promise<unknown> {
    const result = await this.rpc.request('initialize', {
      clientInfo: { name: 'superr', title: 'SuperR', version: '0.1.1' }, capabilities: {},
    });
    this.rpc.notify('initialized', {});
    this.initialized = true;
    return result;
  }

  async models(): Promise<unknown> { this.check(); return this.rpc.request('model/list', {}); }
  async startThread(cwd: string, model?: string): Promise<Obj> {
    this.check();
    this.checkWorkspace(cwd);
    const result = await this.rpc.request('thread/start', {
      cwd, ...(model ? { model } : {}), approvalPolicy: 'on-request', sandbox: 'read-only',
    });
    return this.remember(result);
  }
  async resumeThread(threadId: string, cwd: string): Promise<Obj> {
    this.check();
    if (!threadId) throw new Error('A thread ID is required');
    this.checkWorkspace(cwd);
    return this.remember(await this.rpc.request('thread/resume', {
      threadId, cwd, approvalPolicy: 'on-request', sandbox: 'read-only',
    }));
  }
  async prompt(threadId: string, text: string): Promise<unknown> {
    this.checkThread(threadId);
    if (!text.trim()) throw new Error('A message is required');
    if (this.activeTurns.has(threadId)) throw new Error('A turn is already running');
    const active: { id?: string; completed: Set<string> } = { completed: new Set<string>() };
    this.activeTurns.set(threadId, active);
    try {
      const result = await this.rpc.request('turn/start', { threadId, input: [{ type: 'text', text, text_elements: [] }] });
      if (!obj(result) || !obj(result.turn) || typeof result.turn.id !== 'string' || !result.turn.id)
        throw new Error('Agent returned an invalid turn');
      active.id = result.turn.id;
      if (active.completed.has(active.id)) this.activeTurns.delete(threadId);
      return result;
    } catch (error) { this.activeTurns.delete(threadId); throw error; }
  }
  async cancel(threadId: string, turnId: string): Promise<void> {
    this.checkThread(threadId);
    if (!turnId || this.activeTurns.get(threadId)?.id !== turnId) throw new Error('Unknown active turn');
    await this.rpc.request('turn/interrupt', { threadId, turnId });
  }
  shutdown(): void { this.initialized = false; this.threads.clear(); this.activeTurns.clear(); this.rpc.shutdown(); }
  private check(): void { if (!this.initialized) throw new Error('Agent connection is not initialized'); }
  private checkThread(id: string): void { this.check(); if (!this.threads.has(id)) throw new Error('Unknown agent thread'); }
  private checkWorkspace(cwd: string): void {
    if (!isAbsolute(cwd) || resolve(cwd) !== this.workspace) throw new Error('Workspace does not match the authorized directory');
  }
  private remember(result: unknown): Obj {
    if (!obj(result) || !obj(result.thread) || typeof result.thread.id !== 'string' || !result.thread.id)
      throw new Error('Agent returned an invalid thread');
    this.threads.add(result.thread.id);
    return result;
  }
}
