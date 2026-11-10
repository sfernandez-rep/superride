// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import { createHash } from 'node:crypto';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import type { ChatGptAccounts } from './chatgpt-accounts';
import { AI_STUDIO_KEY_PAGE, AI_STUDIO_LIMITS_PAGE, GEMINI_FREE_MODELS, GeminiApi, GeminiApiError, GeminiContent,
  GeminiErrorKind, GeminiMessage, GeminiModel, GeminiPart, QuotaInfo } from './gemini-api';
import { ContextError, DisclosedFile, ProjectContext, parseContext } from './project-context';
import type { EditProposal } from './edit-proposal';

export type ChatProvider = 'gemini-api' | 'gemini' | 'codex';
export interface ChatStatus {
  provider: ChatProvider;
  installed: boolean;
  authentication: 'connected' | 'signed_out' | 'unknown';
  readOnlyAvailable: false;
  /** Only the text-only Gemini API mode can chat; agents stay closed until isolation is verified. */
  chatAvailable: boolean;
}
export type ChatErrorKind = GeminiErrorKind | 'busy' | 'no_key' | 'storage' | 'context';
export interface KeyResult { ok: boolean; kind?: ChatErrorKind; models?: GeminiModel[] }
export interface SendResult { status: 'completed' | 'cancelled' | 'incomplete' | 'error'; kind?: ChatErrorKind;
  finishReason?: string; quota?: QuotaInfo; detail?: string; files?: DisclosedFile[];
  /** Every proposal of this turn again: events and the reply travel separately, so the panel may get either first. */
  proposals?: EditProposal[] }
/** Streamed text, or a report of what was disclosed: attached context or a function SuperR ran. */
export interface ChatEvent { provider: 'gemini-api'; turn: string; text?: string; kind?: 'context' | 'tool' | 'proposal';
  tool?: string; files?: DisclosedFile[]; proposal?: EditProposal }
export interface SecretStore {
  loadSecret(id: string): Promise<string | null>;
  saveSecret(id: string, secret: string): Promise<void>;
  remove(id: string): Promise<void>;
}
export interface ChatBridgeOptions {
  searchPath?: string;
  secrets?: () => Promise<SecretStore>;
  gemini?: GeminiApi;
  onEvent?: (event: ChatEvent) => void;
  /** Expands the IDE's aliased paths (~/...) to absolute ones before they are checked. */
  resolvePath?: (aliased: string) => string;
  /** The reverse, so the IDE can open the file a proposal targets. */
  aliasPath?: (absolute: string) => string;
}

const GEMINI_KEY_ID = createHash('md5').update('superr-gemini-api-key').digest('hex');
const MAX_HISTORY_MESSAGES = 20;
const MAX_HISTORY_CHARS = 200000;
/** Function rounds per message; each round is one more request against the user's quota. */
const MAX_TOOL_ROUNDS = 4;

/**
 * Explicit, fail-closed surface. No agent process is launched without a verified
 * boundary. The Gemini API mode sends the typed conversation and, only when the
 * user chose a file or project context, what ProjectContext discloses through
 * read-only functions; it never writes files or runs commands. The API key never
 * leaves the main process.
 */
export class ChatBridge {
  private closed = false;
  private signingIn = false;
  private history: GeminiMessage[] = [];
  private active: AbortController | undefined;
  private readonly searchPath: string;
  private readonly gemini: GeminiApi;
  constructor(private readonly accounts: () => Promise<ChatGptAccounts>,
    private readonly openExternal: (url: string) => Promise<void>,
    private readonly options: ChatBridgeOptions = {}) {
    this.searchPath = options.searchPath ?? process.env.PATH ?? '';
    this.gemini = options.gemini ?? new GeminiApi();
  }

  async status(provider: unknown): Promise<ChatStatus> {
    const name = this.provider(provider);
    if (name === 'gemini-api') {
      const connected = (await this.key()) !== null;
      return { provider: name, installed: true, authentication: connected ? 'connected' : 'signed_out',
        readOnlyAvailable: false, chatAvailable: connected };
    }
    const installed = await this.installed(name);
    let authentication: ChatStatus['authentication'] = 'unknown';
    if (name === 'codex') {
      const list = await (await this.accounts()).list();
      authentication = list.some(account => account.state === 'connected') ? 'connected' : 'signed_out';
    }
    return { provider: name, installed, authentication, readOnlyAvailable: false, chatAvailable: false };
  }

  async signIn(provider: unknown): Promise<ChatStatus> {
    const name = this.provider(provider);
    // Antigravity's terms and FAQ (checked 2026-11-10) do not support wrapping
    // agy in third-party applications under consumer plans, and treat third-party
    // access with an Antigravity login as a breach. Do not offer that sign-in.
    if (name !== 'codex') throw new Error('Google consumer sign-in is not offered for third-party applications');
    if (this.signingIn) throw new Error('Sign-in is already running');
    this.signingIn = true;
    try {
      const flow = await (await this.accounts()).beginSignIn();
      try { await this.openExternal(flow.authorizeUrl); }
      catch { flow.cancel(); throw new Error('Could not open the authorization page'); }
      await flow.result;
      return await this.status(name);
    } finally { this.signingIn = false; }
  }

  /** Opens a Google AI Studio page; the URLs are fixed here, never supplied by the renderer. */
  async openKeyPage(provider: unknown, page?: unknown): Promise<void> {
    this.geminiApi(provider);
    await this.openExternal(page === 'limits' ? AI_STUDIO_LIMITS_PAGE : AI_STUDIO_KEY_PAGE);
  }

  /** Checks the key with Google, then stores it encrypted. The key is never returned. */
  async setKey(provider: unknown, key: unknown): Promise<KeyResult> {
    this.geminiApi(provider);
    const value = typeof key === 'string' ? key.trim() : '';
    if (value.length < 10 || value.length > 4096 || /\s/.test(value)) return { ok: false, kind: 'invalid_key' };
    let models: GeminiModel[];
    try { models = await this.gemini.models(value); }
    catch (error: unknown) { return { ok: false, kind: kindOf(error) }; }
    try { await (await this.secrets()).saveSecret(GEMINI_KEY_ID, value); }
    catch { return { ok: false, kind: 'storage' }; }
    return { ok: true, models };
  }

  async forgetKey(provider: unknown): Promise<ChatStatus> {
    this.geminiApi(provider);
    this.active?.abort();
    this.history = [];
    await (await this.secrets()).remove(GEMINI_KEY_ID);
    return this.status(provider);
  }

  async models(provider: unknown): Promise<KeyResult> {
    this.geminiApi(provider);
    const key = await this.key();
    if (key === null) return { ok: false, kind: 'no_key' };
    try { return { ok: true, models: await this.gemini.models(key) }; }
    catch (error: unknown) { return { ok: false, kind: kindOf(error) }; }
  }

  /** Stops a running answer (it ends as cancelled) and forgets the conversation; the key stays. */
  async newChat(provider: unknown): Promise<void> {
    this.geminiApi(provider);
    this.active?.abort();
    this.history = [];
  }

  async send(provider: unknown, message: unknown, model?: unknown, turn?: unknown,
    context?: unknown): Promise<SendResult> {
    const name = this.provider(provider);
    if (typeof message !== 'string' || !message.trim() || message.length > 100000) throw new Error('Invalid message');
    if (name !== 'gemini-api') throw new Error('Agent read-only isolation is not verified');
    if (typeof model !== 'string' || !GEMINI_FREE_MODELS.some(m => m.id === model)) throw new Error('Invalid model');
    if (typeof turn !== 'string' || !/^[A-Za-z0-9_-]{1,40}$/.test(turn)) throw new Error('Invalid turn');
    let parsed;
    try { parsed = parseContext(context); }
    catch (error: unknown) { return { status: 'error', kind: 'context', detail: (error as ContextError).code }; }
    const resolve = this.options.resolvePath;
    if (resolve) {
      const document = <T extends { path?: string }>(d: T): T => d.path ? { ...d, path: resolve(d.path) } : d;
      parsed = { ...parsed, ...(parsed.projectRoot ? { projectRoot: resolve(parsed.projectRoot) } : {}),
        ...(parsed.active ? { active: document(parsed.active) } : {}),
        ...(parsed.open ? { open: parsed.open.map(document) } : {}) };
    }
    if (this.active) return { status: 'error', kind: 'busy' };
    const controller = new AbortController();
    this.active = controller;
    const emit = (event: Omit<ChatEvent, 'provider' | 'turn'>) => {
      if (!controller.signal.aborted) this.options.onEvent?.({ provider: 'gemini-api', turn, ...event });
    };
    let scope: ProjectContext | undefined;
    try {
      const key = await this.key();
      if (key === null) return { status: 'error', kind: 'no_key' };
      scope = await ProjectContext.open(parsed, { aliasPath: this.options.aliasPath,
        homes: this.options.resolvePath ? [this.options.resolvePath('~')] : [] });
      const attachment = scope.attachment();
      if (scope.files.length) emit({ kind: 'context', files: scope.files });
      const conversation = trim([...this.history, { role: 'user', text: message }]);
      const contents: GeminiContent[] = conversation.map(m => ({ role: m.role, parts: [{ text: m.text }] }));
      contents[contents.length - 1] = { role: 'user', parts: [{ text: attachment + message }] };
      const request = { contents, systemInstruction: await scope.instruction(), functions: scope.tools() };
      let answer = '';
      const proposals: EditProposal[] = [];
      let result: SendResult = { status: 'completed' };
      for (let round = 0; ; round++) {
        const onText = (text: string) => { answer += text; emit({ text }); };
        const step = await this.gemini.generate(key, model, request, onText, controller.signal);
        if (step.status === 'cancelled') return { status: 'cancelled' };
        result = { status: step.status, ...(step.finishReason ? { finishReason: step.finishReason } : {}) };
        if (!step.calls.length) break;
        if (round >= MAX_TOOL_ROUNDS) { result = { status: 'incomplete', finishReason: 'TOOL_ROUNDS' }; break; }
        // Gemini needs its own content back unchanged (thought signatures), then the function results.
        contents.push(step.content);
        const responses: GeminiPart[] = [];
        for (const call of step.calls) {
          const done = await scope.call(call.name, call.args);
          emit({ kind: 'tool', tool: call.name, files: done.files });
          if (done.proposal) { proposals.push(done.proposal); emit({ kind: 'proposal', proposal: done.proposal }); }
          const id = call.id ? { id: call.id } : {};
          responses.push({ functionResponse: { name: call.name, response: done.response, ...id } });
        }
        if (controller.signal.aborted) return { status: 'cancelled' };
        contents.push({ role: 'user', parts: responses });
      }
      // Keep only complete exchanges (plain text) so the next turn alternates user/model.
      if (answer && !controller.signal.aborted) this.history = trim([...conversation, { role: 'model', text: answer }]);
      return { ...result, ...(scope.files.length ? { files: scope.files } : {}),
        ...(proposals.length ? { proposals } : {}) };
    } catch (error: unknown) {
      if (controller.signal.aborted) return { status: 'cancelled' };
      const files = scope?.files.length ? { files: scope.files } : {};
      if (error instanceof ContextError) return { status: 'error', kind: 'context', detail: error.code };
      if (!(error instanceof GeminiApiError)) return { status: 'error', kind: 'storage', ...files };
      return { status: 'error', kind: error.kind, ...(error.quota ? { quota: error.quota } : {}), ...files };
    } finally { if (this.active === controller) this.active = undefined; }
  }

  async cancel(provider: unknown): Promise<void> {
    const name = this.provider(provider);
    if (name !== 'gemini-api' || !this.active) throw new Error('No active agent turn');
    this.active.abort();
  }

  shutdown(): void { this.closed = true; this.active?.abort(); this.history = []; }

  private provider(value: unknown): ChatProvider {
    if (this.closed) throw new Error('Chat is closed');
    if (value !== 'gemini-api' && value !== 'gemini' && value !== 'codex') throw new Error('Invalid provider');
    return value;
  }
  private geminiApi(value: unknown): void {
    if (this.provider(value) !== 'gemini-api') throw new Error('Only the Gemini API mode uses an API key');
  }
  private async secrets(): Promise<SecretStore> {
    if (!this.options.secrets) throw new Error('Protected credential storage is unavailable');
    return this.options.secrets();
  }
  private async key(): Promise<string | null> {
    return (await this.secrets()).loadSecret(GEMINI_KEY_ID);
  }
  private async installed(provider: 'gemini' | 'codex'): Promise<boolean> {
    const names = process.platform === 'win32' ? (provider === 'gemini' ? ['agy.exe', 'agy.cmd'] : ['codex.exe', 'codex.cmd']) :
      [provider === 'gemini' ? 'agy' : 'codex'];
    for (const dir of this.searchPath.split(path.delimiter)) {
      if (!path.isAbsolute(dir)) continue;
      for (const name of names) {
        try { if ((await fs.stat(path.join(dir, name))).isFile()) return true; } catch { /* not installed here */ }
      }
    }
    return false;
  }
}

function kindOf(error: unknown): ChatErrorKind {
  return error instanceof GeminiApiError ? error.kind : 'connection';
}

/** Drops the oldest messages beyond the limits, starting the history with a user message. */
function trim(messages: GeminiMessage[]): GeminiMessage[] {
  let result = messages.slice(-MAX_HISTORY_MESSAGES);
  while (result.length > 1 && (result[0].role !== 'user' || result.reduce((n, m) => n + m.text.length, 0) > MAX_HISTORY_CHARS))
    result = result.slice(1);
  return result;
}
