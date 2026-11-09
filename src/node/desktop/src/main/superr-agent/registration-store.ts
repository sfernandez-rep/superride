// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import * as fs from 'node:fs/promises';
import { constants } from 'node:fs';
import { randomBytes, randomUUID } from 'node:crypto';
import * as path from 'node:path';

interface Registration { clientId: string; subjectHash?: string }
interface Registry { version: 1; hostId: string; registrations: Record<string, Registration> }
const profilePattern = /^[a-f0-9]{32}$/;
const clientPattern = /^[A-Za-z0-9._-]{1,256}$/;
const hostPattern = /^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Nonsecret registration IDs only; account identities and tokens stay encrypted. */
export class RegistrationStore {
  private constructor(private readonly root: string) {}
  static async open(root: string): Promise<RegistrationStore> {
    if (!path.isAbsolute(root)) throw new Error('An absolute private directory is required');
    await fs.mkdir(root, { recursive: true, mode: 0o700 });
    const info = await fs.lstat(root);
    if (!info.isDirectory() || info.isSymbolicLink()) throw new Error('Invalid registration directory');
    return new RegistrationStore(await fs.realpath(root));
  }

  async readOrCreate(): Promise<Registry> {
    return this.locked(async () => {
      const existing = await this.read();
      if (existing) return existing;
      const registry: Registry = { version: 1, hostId: `urn:uuid:${randomUUID()}`, registrations: {} };
      await this.write(registry);
      return registry;
    });
  }

  async remember(profileId: string, clientId: string): Promise<void> {
    if (!profilePattern.test(profileId) || !clientPattern.test(clientId) || clientId === 'dynamic_agent_client')
      throw new Error('Invalid client registration');
    await this.locked(async () => {
      const registry = await this.read();
      if (!registry) throw new Error('Host ID has not been created');
      if (registry.registrations[profileId] && registry.registrations[profileId].clientId !== clientId)
        throw new Error('Cannot replace a different registration');
      if (!registry.registrations[profileId]) registry.registrations[profileId] = { clientId };
      await this.write(registry);
    });
  }

  async rememberSubject(profileId: string, subjectHash: string): Promise<void> {
    if (!profilePattern.test(profileId) || !/^[a-f0-9]{64}$/.test(subjectHash)) throw new Error('Invalid account identity');
    await this.locked(async () => {
      const registry = await this.read();
      const registration = registry?.registrations[profileId];
      if (!registry || !registration) throw new Error('Unknown client registration');
      if (registration.subjectHash && registration.subjectHash !== subjectHash) throw new Error('Account identity cannot change');
      registration.subjectHash = subjectHash;
      await this.write(registry);
    });
  }

  private async read(): Promise<Registry | null> {
    const file = path.join(this.root, 'registrations.json');
    let raw: string;
    try {
      const info = await fs.lstat(file);
      if (!info.isFile() || info.isSymbolicLink() || info.size > 1024 * 1024) throw new Error('Invalid registration file');
      const handle = await fs.open(file, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
      try {
        const bytes = Buffer.alloc(info.size + 1);
        let count = 0;
        while (count < bytes.length) {
          const chunk = await handle.read(bytes, count, bytes.length - count, count);
          if (!chunk.bytesRead) break;
          count += chunk.bytesRead;
        }
        if (count !== info.size) throw new Error('Registration file changed during read');
        raw = new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, count));
      } finally { await handle.close(); }
    } catch (error: unknown) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null;
      throw new Error('Cannot read registration file');
    }
    let value: unknown;
    try { value = JSON.parse(raw); } catch { throw new Error('Invalid registration file'); }
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid registration file');
    const data = value as Record<string, unknown>;
    if (data.version !== 1 || typeof data.hostId !== 'string' || !hostPattern.test(data.hostId) ||
        !data.registrations || typeof data.registrations !== 'object' || Array.isArray(data.registrations))
      throw new Error('Invalid registration file');
    const registrations: Record<string, Registration> = Object.create(null);
    for (const [id, entry] of Object.entries(data.registrations)) {
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new Error('Invalid registration file');
      const value = entry as Record<string, unknown>;
      if (!profilePattern.test(id) || typeof value.clientId !== 'string' || !clientPattern.test(value.clientId) ||
          value.clientId === 'dynamic_agent_client' ||
          (value.subjectHash !== undefined && (typeof value.subjectHash !== 'string' || !/^[a-f0-9]{64}$/.test(value.subjectHash))))
        throw new Error('Invalid registration file');
      registrations[id] = { clientId: value.clientId,
        ...(typeof value.subjectHash === 'string' ? { subjectHash: value.subjectHash } : {}) };
    }
    return { version: 1, hostId: data.hostId, registrations };
  }

  private async write(registry: Registry): Promise<void> {
    const file = path.join(this.root, 'registrations.json');
    const temp = path.join(this.root, `.registry-${randomBytes(16).toString('hex')}.tmp`);
    let created = false;
    try {
      const handle = await fs.open(temp, 'wx', 0o600); created = true;
      try { await handle.writeFile(JSON.stringify(registry), 'utf8'); await handle.sync(); }
      finally { await handle.close(); }
      await fs.rename(temp, file); created = false;
    } finally { if (created) await fs.unlink(temp).catch(() => {}); }
  }

  private async locked<T>(action: () => Promise<T>): Promise<T> {
    const file = path.join(this.root, '.registrations.lock');
    let lock;
    try { lock = await fs.open(file, 'wx', 0o600); }
    catch (error: unknown) {
      if ((error as NodeJS.ErrnoException).code === 'EEXIST') throw new Error('Registration store is locked');
      throw new Error('Cannot lock registration store');
    }
    try { return await action(); }
    finally { await lock.close(); await fs.unlink(file); }
  }
}
