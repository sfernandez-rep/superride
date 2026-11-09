// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import { AcpClient } from './acp-client';
import { CodexClient } from './codex-client';

type Obj = Record<string, unknown>;
function obj(value: unknown): value is Obj { return typeof value === 'object' && value !== null && !Array.isArray(value); }
export type TurnOutcome = { status: 'completed' | 'cancelled' | 'incomplete' | 'failed' };
export interface AgentProvider {
  connect(): Promise<unknown>;
  createSession(cwd: string): Promise<string>;
  resumeSession(id: string, cwd: string): Promise<void>;
  sendMessage(id: string, text: string): Promise<TurnOutcome>;
  cancelRequest(id: string): Promise<void>;
  shutdown(): void;
}

/** ACP sendMessage resolves only when session/prompt returns its stop reason. */
export class AntigravityProvider implements AgentProvider {
  constructor(private readonly client: AcpClient) {}
  connect(): Promise<unknown> { return this.client.initialize(); }
  async createSession(cwd: string): Promise<string> { return (await this.client.createSession(cwd)).sessionId as string; }
  async resumeSession(id: string, cwd: string): Promise<void> { await this.client.loadSession(id, cwd); }
  async sendMessage(id: string, text: string): Promise<TurnOutcome> {
    const result = await this.client.prompt(id, text);
    if (!obj(result) || typeof result.stopReason !== 'string') throw new Error('Agent returned an invalid turn result');
    switch (result.stopReason) {
      case 'end_turn': return { status: 'completed' };
      case 'cancelled': return { status: 'cancelled' };
      case 'max_tokens': case 'max_turn_requests': case 'refusal': return { status: 'incomplete' };
      default: return { status: 'incomplete' };
    }
  }
  async cancelRequest(id: string): Promise<void> { this.client.cancel(id); }
  shutdown(): void { this.client.shutdown(); }
}

type PendingTurn = { turnId?: string; early: Map<string, TurnOutcome>; cancelRequested: boolean;
  resolve: (result: TurnOutcome) => void; reject: (error: Error) => void };

/**
 * Codex returns from turn/start before the turn finishes. Route its notifications
 * to onNotification so sendMessage has the same completion semantics as ACP.
 */
export class CodexProvider implements AgentProvider {
  private readonly pending = new Map<string, PendingTurn>();
  constructor(private readonly client: CodexClient) {}
  connect(): Promise<unknown> { return this.client.initialize(); }
  async createSession(cwd: string): Promise<string> {
    const result = await this.client.startThread(cwd);
    return (result.thread as Obj).id as string;
  }
  async resumeSession(id: string, cwd: string): Promise<void> { await this.client.resumeThread(id, cwd); }
  async sendMessage(id: string, text: string): Promise<TurnOutcome> {
    if (this.pending.has(id)) throw new Error('A turn is already running');
    let resolve!: (result: TurnOutcome) => void;
    let reject!: (error: Error) => void;
    const completion = new Promise<TurnOutcome>((accept, fail) => { resolve = accept; reject = fail; });
    void completion.catch(() => {});
    const pending: PendingTurn = { early: new Map(), cancelRequested: false, resolve, reject };
    this.pending.set(id, pending);
    void this.client.prompt(id, text).then(async result => {
      if (this.pending.get(id) !== pending) return;
      if (!obj(result) || !obj(result.turn) || typeof result.turn.id !== 'string') throw new Error('Agent returned an invalid turn');
      pending.turnId = result.turn.id;
      const early = pending.early.get(pending.turnId);
      if (early) { this.pending.delete(id); pending.resolve(early); return; }
      if (pending.cancelRequested) await this.client.cancel(id, pending.turnId);
    }).catch(() => {
      if (this.pending.get(id) === pending) { this.pending.delete(id); pending.reject(new Error('Agent turn could not start')); }
    });
    return completion;
  }
  async cancelRequest(id: string): Promise<void> {
    const pending = this.pending.get(id);
    if (!pending) throw new Error('No active turn');
    if (pending.turnId) await this.client.cancel(id, pending.turnId);
    else pending.cancelRequested = true;
  }
  onNotification(method: string, params: unknown): void {
    if (method !== 'turn/completed' || !obj(params) || typeof params.threadId !== 'string' ||
        !obj(params.turn) || typeof params.turn.id !== 'string') return;
    const pending = this.pending.get(params.threadId);
    if (!pending) return;
    const outcome: TurnOutcome = { status: params.turn.status === 'completed' ? 'completed' :
      params.turn.status === 'interrupted' ? 'cancelled' : 'failed' };
    if (pending.turnId === params.turn.id) { this.pending.delete(params.threadId); pending.resolve(outcome); }
    else if (!pending.turnId && pending.early.size < 16) pending.early.set(params.turn.id, outcome);
  }
  onExit(): void {
    for (const pending of this.pending.values()) pending.reject(new Error('Agent process exited'));
    this.pending.clear();
  }
  shutdown(): void { this.onExit(); this.client.shutdown(); }
}
