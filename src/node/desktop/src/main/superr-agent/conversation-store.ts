// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import * as fs from 'node:fs/promises';
import { constants } from 'node:fs';
import * as path from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';

export interface ConversationMessage {
  role: 'user' | 'assistant';
  text: string;
  files: string[];
  time: string;
}
export interface Conversation {
  version: 1;
  id: string;
  project: string | null;
  provider: 'antigravity' | 'codex';
  sessionId: string | null;
  created: string;
  updated: string;
  messages: ConversationMessage[];
}
const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const maxBytes = 4 * 1024 * 1024;
const object = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);
const timestamp = (value: unknown): value is string => typeof value === 'string' &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value) && Number.isFinite(Date.parse(value));

/** Private local history; callers supply only intentionally disclosed chat text. */
export class ConversationStore {
  private constructor(private readonly root: string) {}
  static async open(root: string): Promise<ConversationStore> {
    if (!path.isAbsolute(root)) throw new Error('An absolute history directory is required');
    await fs.mkdir(root, { recursive: true, mode: 0o700 });
    const stat = await fs.lstat(root);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Invalid history directory');
    return new ConversationStore(await fs.realpath(root));
  }

  async create(project: string | null, provider: Conversation['provider']): Promise<Conversation> {
    if ((project !== null && (!path.isAbsolute(project) || project.length > 4096)) ||
        (provider !== 'antigravity' && provider !== 'codex')) throw new Error('Invalid conversation');
    const now = new Date().toISOString();
    const value: Conversation = { version: 1, id: randomUUID(), project, provider, sessionId: null,
      created: now, updated: now, messages: [] };
    await this.save(value);
    return value;
  }

  async list(project: string | null): Promise<Conversation[]> {
    const names = await fs.readdir(this.root);
    if (names.length > 10000) throw new Error('Too many history files');
    const result: Conversation[] = [];
    for (const name of names) {
      if (!name.endsWith('.json') || !idPattern.test(name.slice(0, -5))) continue;
      const value = await this.read(name.slice(0, -5));
      if (value && value.project === project) result.push(value);
    }
    return result.sort ( (a, b) => b.updated.localeCompare(a.updated));
  }

  async read(id: string): Promise<Conversation | null> {
    this.checkId(id);
    const file = path.join(this.root, `${id}.json`);
    let handle;
    try {
      const stat = await fs.lstat(file);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > maxBytes) throw new Error('Invalid history file');
      handle = await fs.open(file, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
      const bytes = Buffer.alloc(maxBytes + 1);
      let count = 0;
      while (count < bytes.length) {
        const part = await handle.read(bytes, count, bytes.length - count, count);
        if (!part.bytesRead) break;
        count += part.bytesRead;
      }
      if (count > maxBytes) throw new Error('Invalid history file');
      const data: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, count)));
      const value = this.validate(data);
      if (value.id !== id) throw new Error('Invalid history file');
      return value;
    } catch (error: unknown) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null;
      throw new Error('Cannot read conversation');
    } finally { await handle?.close(); }
  }

  async save(conversation: Conversation): Promise<void> {
    const value = this.validate(conversation);
    const data = JSON.stringify(value);
    if (Buffer.byteLength(data) > maxBytes) throw new Error('Conversation is too large');
    await this.locked(value.id, async () => {
      const file = path.join(this.root, `${value.id}.json`);
      const temp = path.join(this.root, `.history-${randomBytes(16).toString('hex')}.tmp`);
      let created = false;
      try {
        const handle = await fs.open(temp, 'wx', 0o600); created = true;
        try { await handle.writeFile(data, 'utf8'); await handle.sync(); } finally { await handle.close(); }
        await fs.rename(temp, file); created = false;
      } finally { if (created) await fs.unlink(temp).catch(() => {}); }
    });
  }

  async delete(id: string): Promise<void> {
    this.checkId(id);
    await this.locked(id, async () => { await fs.unlink(path.join(this.root, `${id}.json`)).catch((error: NodeJS.ErrnoException) => {
      if (error.code !== 'ENOENT') throw error;
    }); });
  }

  private validate(data: unknown): Conversation {
    if (!object(data) || data.version !== 1 || typeof data.id !== 'string' || !idPattern.test(data.id) ||
        (data.project !== null && (typeof data.project !== 'string' || !path.isAbsolute(data.project) || data.project.length > 4096)) ||
        (data.provider !== 'antigravity' && data.provider !== 'codex') ||
        (data.sessionId !== null && (typeof data.sessionId !== 'string' || data.sessionId.length > 1024)) ||
        !timestamp(data.created) || !timestamp(data.updated) || !Array.isArray(data.messages) || data.messages.length > 10000)
      throw new Error('Invalid conversation');
    const messages: ConversationMessage[] = data.messages.map(message => {
      if (!object(message) || (message.role !== 'user' && message.role !== 'assistant') ||
          typeof message.text !== 'string' || message.text.length > maxBytes || !timestamp(message.time) ||
          !Array.isArray(message.files) || message.files.length > 1000 ||
          !message.files.every((file: unknown) => typeof file === 'string' && file.length <= 4096))
        throw new Error('Invalid conversation message');
      return { role: message.role, text: message.text, files: [...message.files] as string[], time: message.time };
    });
    return { version: 1, id: data.id, project: data.project, provider: data.provider,
      sessionId: data.sessionId, created: data.created, updated: data.updated, messages } as Conversation;
  }
  private checkId(id: string): void { if (!idPattern.test(id)) throw new Error('Invalid conversation ID'); }
  private async locked<T>(id: string, action: () => Promise<T>): Promise<T> {
    const file = path.join(this.root, `.${id}.lock`);
    let lock;
    try { lock = await fs.open(file, 'wx', 0o600); } catch { throw new Error('Conversation is locked'); }
    try { return await action(); } finally { await lock.close(); await fs.unlink(file); }
  }
}
