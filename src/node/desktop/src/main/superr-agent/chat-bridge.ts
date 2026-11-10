// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import type { ChatGptAccounts } from './chatgpt-accounts';

export type ChatProvider = 'gemini' | 'codex';
export interface ChatStatus {
  provider: ChatProvider;
  installed: boolean;
  authentication: 'connected' | 'signed_out' | 'unknown';
  readOnlyAvailable: false;
}

/** Explicit, fail-closed surface. No process is launched without a verified boundary. */
export class ChatBridge {
  private closed = false;
  private signingIn = false;
  constructor(private readonly accounts: () => Promise<ChatGptAccounts>,
    private readonly openExternal: (url: string) => Promise<void>,
    private readonly searchPath: string = process.env.PATH ?? '') {}

  async status(provider: unknown): Promise<ChatStatus> {
    const name = this.provider(provider);
    const installed = await this.installed(name);
    let authentication: ChatStatus['authentication'] = 'unknown';
    if (name === 'codex') {
      const list = await (await this.accounts()).list();
      authentication = list.some(account => account.state === 'connected') ? 'connected' : 'signed_out';
    }
    return { provider: name, installed, authentication, readOnlyAvailable: false };
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

  async send(provider: unknown, message: unknown): Promise<never> {
    this.provider(provider);
    if (typeof message !== 'string' || !message.trim() || message.length > 100000) throw new Error('Invalid message');
    throw new Error('Agent read-only isolation is not verified');
  }
  async cancel(provider: unknown): Promise<never> {
    this.provider(provider);
    throw new Error('No active agent turn');
  }
  shutdown(): void { this.closed = true; }
  private provider(value: unknown): ChatProvider {
    if (this.closed) throw new Error('Chat is closed');
    if (value !== 'gemini' && value !== 'codex') throw new Error('Invalid provider');
    return value;
  }
  private async installed(provider: ChatProvider): Promise<boolean> {
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
