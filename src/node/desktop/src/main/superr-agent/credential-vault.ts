// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import * as fs from 'node:fs/promises';
import { constants } from 'node:fs';
import { randomBytes } from 'node:crypto';
import * as path from 'node:path';
import type { ChatGptGrant } from './chatgpt-auth';

export interface CredentialCodec {
  encrypt(plaintext: string): Buffer;
  decrypt(ciphertext: Buffer): string;
}
export interface StoredGrant extends ChatGptGrant { savedAt: number }

/** Per-user encrypted storage; codec must use the OS keychain, never plaintext. */
export class CredentialVault {
  private constructor(private readonly root: string, private readonly codec: CredentialCodec) {}
  static async open(root: string, codec: CredentialCodec): Promise<CredentialVault> {
    if (!path.isAbsolute(root)) throw new Error('A private absolute storage directory is required');
    await fs.mkdir(root, { recursive: true, mode: 0o700 });
    const info = await fs.lstat(root);
    if (!info.isDirectory() || info.isSymbolicLink()) throw new Error('Invalid credential storage directory');
    return new CredentialVault(await fs.realpath(root), codec);
  }

  async save(id: string, grant: StoredGrant): Promise<void> {
    await this.withLock(id, () => this.saveUnlocked(id, grant));
  }

  /** Bind a profile to one verified identity, including concurrent sign-ins. */
  async saveVerified(id: string, grant: StoredGrant): Promise<void> {
    await this.withLock(id, async () => {
      const current = await this.load(id);
      if (current && (current.clientId !== grant.clientId || current.hostId !== grant.hostId || current.subject !== grant.subject))
        throw new Error('Credential identity cannot replace another account');
      await this.saveUnlocked(id, grant);
    });
  }

  private async saveUnlocked(id: string, grant: StoredGrant): Promise<void> {
    const destination = this.file(id);
    if (!validGrant(grant)) throw new Error('Invalid credential grant');
    const encrypted = this.codec.encrypt(JSON.stringify(grant));
    if (!Buffer.isBuffer(encrypted) || encrypted.length === 0 || encrypted.length > 1024 * 1024)
      throw new Error('Credential encryption failed');
    const temp = path.join(this.root, `.credentials-${randomBytes(16).toString('hex')}.tmp`);
    let created = false;
    try {
      const handle = await fs.open(temp, 'wx', 0o600);
      created = true;
      try { await handle.writeFile(encrypted); await handle.sync(); }
      finally { await handle.close(); }
      await fs.rename(temp, destination);
      created = false;
    } finally {
      if (created) await fs.unlink(temp).catch(() => {});
    }
  }

  async load(id: string): Promise<StoredGrant | null> {
    const file = this.file(id);
    let handle;
    try {
      if ((await fs.lstat(file)).isSymbolicLink()) throw new Error('Invalid credential storage');
      handle = await fs.open(file, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
    }
    catch (error: unknown) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null;
      throw new Error('Cannot open credential storage');
    }
    try {
      const info = await handle.stat();
      if (!info.isFile() || info.size <= 0 || info.size > 1024 * 1024) throw new Error('Invalid credential storage');
      const data = Buffer.alloc(info.size + 1);
      let count = 0;
      while (count < data.length) {
        const chunk = await handle.read(data, count, data.length - count, count);
        if (!chunk.bytesRead) break;
        count += chunk.bytesRead;
      }
      if (count !== info.size) throw new Error('Credential storage changed during read');
      const parsed: unknown = JSON.parse(this.codec.decrypt(data.subarray(0, count)));
      if (!validGrant(parsed)) throw new Error('Invalid credential storage');
      return parsed;
    } catch { throw new Error('Cannot decrypt or validate credential storage'); }
    finally { await handle.close(); }
  }

  async remove(id: string): Promise<void> {
    await this.withLock(id, async () => {
      await fs.unlink(this.file(id)).catch((error: NodeJS.ErrnoException) => {
        if (error.code !== 'ENOENT') throw error;
      });
    });
  }

  /** Serializes a read/refresh/write transaction across local SuperR processes. */
  async update(id: string, change: (current: StoredGrant) => Promise<StoredGrant>): Promise<StoredGrant> {
    return this.withLock(id, async () => {
      const current = await this.load(id);
      if (!current) throw new Error('Credential profile does not exist');
      const next = await change(current);
      if (next.clientId !== current.clientId || next.hostId !== current.hostId || next.subject !== current.subject)
        throw new Error('Credential identity cannot change during refresh');
      await this.saveUnlocked(id, next);
      return next;
    });
  }

  /** Run a revocation attempt and clear credentials as one locked operation. */
  async removeAfter<T>(id: string, beforeRemoval: (current: StoredGrant) => Promise<T>): Promise<T> {
    return this.withLock(id, async () => {
      const current = await this.load(id);
      if (!current) throw new Error('Credential profile does not exist');
      const result = await beforeRemoval(current);
      await fs.unlink(this.file(id));
      return result;
    });
  }

  private async withLock<T>(id: string, operation: () => Promise<T>): Promise<T> {
    const lockPath = `${this.file(id)}.lock`;
    let lock;
    try { lock = await fs.open(lockPath, 'wx', 0o600); }
    catch (error: unknown) {
      if ((error as NodeJS.ErrnoException).code === 'EEXIST') throw new Error('Credential profile is locked');
      throw new Error('Cannot lock credential profile');
    }
    try { return await operation(); }
    finally { await lock.close(); await fs.unlink(lockPath); }
  }
  private file(id: string): string {
    if (!/^[a-f0-9]{32}$/.test(id)) throw new Error('Invalid profile identifier');
    return path.join(this.root, `${id}.bin`);
  }
}

function validGrant(value: unknown): value is StoredGrant {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const v = value as Record<string, unknown>;
  const str = (x: unknown) => typeof x === 'string' && x.length > 0 && x.length <= 32768;
  return str(v.clientId) && str(v.hostId) && str(v.subject) && str(v.accessToken) &&
    (v.refreshToken === undefined || str(v.refreshToken)) && str(v.idToken) && typeof v.expiresIn === 'number' &&
    Number.isFinite(v.expiresIn) && v.expiresIn > 0 && typeof v.savedAt === 'number' &&
    Number.isFinite(v.savedAt) && typeof v.sharing === 'boolean' && Array.isArray(v.scopes) &&
    v.scopes.every(str) && v.sharing === v.scopes.includes('chatgpt.tokens.use.direct') &&
    (v.email === undefined || str(v.email));
}
