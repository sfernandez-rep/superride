// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import { createHash, randomBytes } from 'node:crypto';
import * as path from 'node:path';
import { beginChatGptAuthorization, refreshChatGptGrant, signOutChatGpt } from './chatgpt-auth';
import { CredentialCodec, CredentialVault, StoredGrant } from './credential-vault';
import { RegistrationStore } from './registration-store';

export interface AccountStatus {
  id: string;
  state: 'connected' | 'signed_out';
  email?: string;
  sharing: boolean;
  expiresAt?: number;
}
function status(id: string, grant: StoredGrant | null): AccountStatus {
  return grant ? { id, state: 'connected', ...(grant.email ? { email: grant.email } : {}),
    sharing: grant.sharing, expiresAt: grant.savedAt + grant.expiresIn * 1000 } :
    { id, state: 'signed_out', sharing: false };
}

/** Main-process account coordinator; public status results never contain tokens. */
export class ChatGptAccounts {
  private readonly attempts = new Map<string, () => void>();
  private closed = false;
  private constructor(private readonly registry: RegistrationStore, private readonly vault: CredentialVault,
    private readonly request: typeof globalThis.fetch) {}

  static async open(root: string, codec: CredentialCodec, request: typeof globalThis.fetch = globalThis.fetch): Promise<ChatGptAccounts> {
    if (!path.isAbsolute(root)) throw new Error('An absolute private directory is required');
    const registry = await RegistrationStore.open(path.join(root, 'registrations'));
    const vault = await CredentialVault.open(path.join(root, 'credentials'), codec);
    return new ChatGptAccounts(registry, vault, request);
  }

  async list(): Promise<AccountStatus[]> {
    if (this.closed) throw new Error('Account manager is closed');
    const registrations = await this.registry.readOrCreate();
    const result: AccountStatus[] = [];
    for (const id of Object.keys(registrations.registrations).sort()) {
      const grant = await this.vault.load(id);
      if (grant && (grant.hostId !== registrations.hostId || grant.clientId !== registrations.registrations[id].clientId ||
          registrations.registrations[id].subjectHash !== createHash('sha256').update(grant.subject).digest('hex')))
        throw new Error('Account registration and credentials do not match');
      result.push(status(id, grant));
    }
    return result;
  }

  async beginSignIn(existingId?: string): Promise<{
    id: string; authorizeUrl: string; result: Promise<AccountStatus>; cancel: () => void;
  }> {
    if (this.closed) throw new Error('Account manager is closed');
    const registrations = await this.registry.readOrCreate();
    const id = existingId ?? randomBytes(16).toString('hex');
    if (!/^[a-f0-9]{32}$/.test(id)) throw new Error('Invalid profile identifier');
    const registration = registrations.registrations[id];
    const clientId = registration?.clientId;
    if (existingId && !clientId) throw new Error('Unknown account');
    if (this.attempts.has(id)) throw new Error('An account sign-in is already running');
    this.attempts.set(id, () => {});
    try {
      const existing = await this.vault.load(id);
      if (existing && (existing.clientId !== clientId || existing.hostId !== registrations.hostId))
        throw new Error('Account registration and credentials do not match');
      const flow = await beginChatGptAuthorization({ hostId: registrations.hostId, clientId,
        expectedSubject: existing?.subject, expectedSubjectHash: registration?.subjectHash,
        onRegistration: value => this.registry.remember(id, value), fetch: this.request });
      if (this.closed) {
        void flow.result.catch(() => {});
        flow.cancel();
        throw new Error('Account manager is closed');
      }
      this.attempts.set(id, flow.cancel);
      const result = flow.result.then(async grant => {
        if (this.closed) throw new Error('Account manager is closed');
        const stored = { ...grant, savedAt: Date.now() };
        await this.registry.rememberSubject(id, createHash('sha256').update(grant.subject).digest('hex'));
        await this.vault.saveVerified(id, stored);
        return status(id, stored);
      }).finally(() => { this.attempts.delete(id); });
      void result.catch(() => {});
      return { id, authorizeUrl: flow.authorizeUrl, result, cancel: flow.cancel };
    } catch (error) { this.attempts.delete(id); throw error; }
  }

  /** For the provider process only; never expose through a renderer or logs. */
  async accessToken(id: string): Promise<string> {
    if (this.closed) throw new Error('Account manager is closed');
    const registrations = await this.registry.readOrCreate();
    let grant = await this.vault.load(id);
    if (!grant || grant.clientId !== registrations.registrations[id]?.clientId || grant.hostId !== registrations.hostId ||
        registrations.registrations[id]?.subjectHash !== createHash('sha256').update(grant.subject).digest('hex'))
      throw new Error('Account is not connected');
    if (!grant.sharing) throw new Error('ChatGPT plan usage is not enabled for this account');
    if (grant.savedAt + grant.expiresIn * 1000 <= Date.now() + 60000)
      grant = await refreshChatGptGrant(this.vault, id, this.request);
    if (!grant.sharing) throw new Error('ChatGPT plan usage is not enabled for this account');
    return grant.accessToken;
  }

  async signOut(id: string, clearWithoutConfirmation = false): Promise<boolean> {
    if (this.closed) throw new Error('Account manager is closed');
    if (this.attempts.has(id)) throw new Error('Cancel the active sign-in first');
    return signOutChatGpt(this.vault, id, clearWithoutConfirmation, this.request);
  }

  shutdown(): void { this.closed = true; for (const cancel of this.attempts.values()) cancel(); this.attempts.clear(); }
}
