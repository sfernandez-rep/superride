// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only

/**
 * Direct Gemini API client for a user's own Google AI Studio key. Text only:
 * no tools, no files, no project context. The key travels in the
 * x-goog-api-key header (never in a URL) and never appears in an error.
 */
const BASE = 'https://generativelanguage.googleapis.com/v1beta';
export const AI_STUDIO_KEY_PAGE = 'https://aistudio.google.com/apikey';

/** Text models listed with a free tier on Google's pricing page (checked 2026-11-10). */
export const GEMINI_FREE_MODELS: readonly GeminiModel[] = [
  { id: 'gemini-3.6-flash', label: 'Gemini 3.6 Flash' },
  { id: 'gemini-3.8-flash', label: 'Gemini 3.8 Flash' },
  { id: 'gemini-3.5-flash-lite', label: 'Gemini 3.5 Flash-Lite' },
  { id: 'gemini-3.1-flash-lite', label: 'Gemini 3.1 Flash-Lite' },
];
const MAX_RESPONSE = 2 * 1024 * 1024;

export interface GeminiModel { id: string; label: string }
export interface GeminiMessage { role: 'user' | 'model'; text: string }
export type GeminiErrorKind = 'invalid_key' | 'quota' | 'verification' | 'permission' | 'billing' | 'region' |
  'model' | 'blocked' | 'unavailable' | 'connection' | 'invalid_request';

export class GeminiApiError extends Error {
  constructor(readonly kind: GeminiErrorKind, readonly detail = '') { super(`Gemini API: ${kind}`); }
}
export type GeminiFinish = { status: 'completed' | 'cancelled' | 'incomplete'; finishReason?: string };

type Obj = Record<string, unknown>;
function obj(value: unknown): value is Obj { return typeof value === 'object' && value !== null && !Array.isArray(value); }
function validModel(id: string): boolean { return /^gemini-[a-z0-9.-]{1,60}$/.test(id); }

/** Maps a google.rpc.Status error body and HTTP status to a user-facing kind. */
export function classifyError(httpStatus: number, body: unknown): GeminiApiError {
  const error = obj(body) && obj(body.error) ? body.error : {};
  const status = typeof error.status === 'string' ? error.status : '';
  const message = typeof error.message === 'string' ? error.message.slice(0, 300) : '';
  const reasons = Array.isArray(error.details) ?
    error.details.filter(obj).map(d => typeof d.reason === 'string' ? d.reason : '') : [];
  const has = (reason: string) => reasons.includes(reason) || message.includes(reason);
  if (has('API_KEY_INVALID') || has('API_KEY_EXPIRED') || httpStatus === 401 || /api key/i.test(message) && httpStatus < 500)
    return new GeminiApiError('invalid_key', message);
  if (httpStatus === 429 || status === 'RESOURCE_EXHAUSTED') return new GeminiApiError('quota', message);
  if (has('FREE_TIER_VERIFICATION_REQUIRED')) return new GeminiApiError('verification', message);
  if (httpStatus === 402) return new GeminiApiError('billing', message);
  if (status === 'FAILED_PRECONDITION' && /location|region|country/i.test(message)) return new GeminiApiError('region', message);
  if (httpStatus === 404 || status === 'NOT_FOUND') return new GeminiApiError('model', message);
  if (httpStatus === 403 || status === 'PERMISSION_DENIED') return new GeminiApiError('permission', message);
  if (httpStatus >= 500) return new GeminiApiError('unavailable', message);
  return new GeminiApiError('invalid_request', message);
}

export class GeminiApi {
  constructor(private readonly request: typeof globalThis.fetch = globalThis.fetch) {}

  /** Free-tier text models that this key can see; models.list only proves the key exists. */
  async models(key: string, signal?: AbortSignal): Promise<GeminiModel[]> {
    const visible = new Set<string>();
    let pageToken = '';
    for (let page = 0; page < 10; page++) {
      const url = `${BASE}/models?pageSize=1000${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`;
      const body = await this.json(await this.call(url, key, { method: 'GET', signal }));
      if (Array.isArray(body.models))
        for (const model of body.models)
          if (obj(model) && typeof model.name === 'string' && Array.isArray(model.supportedGenerationMethods) &&
              model.supportedGenerationMethods.includes('generateContent'))
            visible.add(model.name.replace(/^models\//, ''));
      if (typeof body.nextPageToken !== 'string' || !body.nextPageToken) break;
      pageToken = body.nextPageToken;
    }
    return GEMINI_FREE_MODELS.filter(model => visible.has(model.id));
  }

  /** Streams one answer; onText receives each text fragment as it arrives. */
  async stream(key: string, model: string, history: readonly GeminiMessage[], onText: (text: string) => void,
    signal: AbortSignal): Promise<GeminiFinish> {
    if (!validModel(model)) throw new GeminiApiError('model');
    if (!history.length || history[history.length - 1].role !== 'user') throw new GeminiApiError('invalid_request');
    let response: Response;
    try {
      response = await this.call(`${BASE}/models/${model}:streamGenerateContent?alt=sse`, key, {
        method: 'POST', signal, headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: history.map(m => ({ role: m.role, parts: [{ text: m.text }] })) }),
      });
    } catch (error: unknown) {
      if (signal.aborted) return { status: 'cancelled' };
      throw error;
    }
    if (!response.body) throw new GeminiApiError('unavailable');
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '', total = 0;
    const state: { finishReason?: string; blocked: boolean } = { blocked: false };
    const line = (raw: string) => {
      const text = raw.trim();
      if (!text.startsWith('data:')) return;
      let chunk: unknown;
      try { chunk = JSON.parse(text.slice(5)); } catch { throw new GeminiApiError('unavailable', 'Malformed stream'); }
      if (!obj(chunk)) return;
      if (obj(chunk.error)) throw classifyError(typeof chunk.error.code === 'number' ? chunk.error.code : 500, chunk);
      if (obj(chunk.promptFeedback) && typeof chunk.promptFeedback.blockReason === 'string') state.blocked = true;
      const candidate = Array.isArray(chunk.candidates) && obj(chunk.candidates[0]) ? chunk.candidates[0] : undefined;
      if (!candidate) return;
      if (typeof candidate.finishReason === 'string') state.finishReason = candidate.finishReason;
      const parts = obj(candidate.content) && Array.isArray(candidate.content.parts) ? candidate.content.parts : [];
      for (const part of parts)
        if (obj(part) && typeof part.text === 'string' && part.text && part.thought !== true) onText(part.text);
    };
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.byteLength;
        if (total > MAX_RESPONSE) throw new GeminiApiError('unavailable', 'Response too large');
        buffer += decoder.decode(value, { stream: true });
        let end;
        while ((end = buffer.indexOf('\n')) >= 0) { line(buffer.slice(0, end)); buffer = buffer.slice(end + 1); }
      }
      line(buffer + decoder.decode());
    } catch (error: unknown) {
      if (signal.aborted) return { status: 'cancelled' };
      if (error instanceof GeminiApiError) throw error;
      throw new GeminiApiError('connection');
    } finally { reader.releaseLock(); }
    const { finishReason } = state;
    if (state.blocked) throw new GeminiApiError('blocked');
    if (finishReason === 'SAFETY' || finishReason === 'PROHIBITED_CONTENT' || finishReason === 'BLOCKLIST')
      throw new GeminiApiError('blocked', finishReason);
    if (finishReason && finishReason !== 'STOP') return { status: 'incomplete', finishReason };
    return { status: 'completed', ...(finishReason ? { finishReason } : {}) };
  }

  private async call(url: string, key: string, init: RequestInit): Promise<Response> {
    if (!key) throw new GeminiApiError('invalid_key');
    let response: Response;
    try {
      response = await this.request(url, { ...init, headers: { ...(init.headers as Record<string, string> | undefined),
        'x-goog-api-key': key }, redirect: 'error' });
    } catch (error: unknown) {
      if (init.signal?.aborted) throw error;
      throw new GeminiApiError('connection');
    }
    if (!response.ok) {
      let body: unknown;
      try { body = await response.json(); } catch { body = undefined; }
      throw classifyError(response.status, body);
    }
    return response;
  }

  private async json(response: Response): Promise<Obj> {
    try {
      const body: unknown = await response.json();
      if (obj(body)) return body;
    } catch { /* reported below */ }
    throw new GeminiApiError('unavailable', 'Malformed response');
  }
}
