// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import * as fs from 'node:fs/promises';
import * as path from 'node:path';

// This is a provider policy, not a complete OS sandbox. Never connect it to a
// real project until behavior against the installed agent has been validated.
const POLICY = JSON.stringify({ permissions: { ask: ['write_file(*)', 'command(*)',
  'unsandboxed(*)', 'read_url(*)', 'execute_url(*)', 'mcp(*)'] } }, null, 2) + '\n';

/** Creates only a SuperR-owned profile and refuses to overwrite other settings. */
export async function prepareAntigravityPolicy(appOwnedBase: string): Promise<string> {
  if (!path.isAbsolute(appOwnedBase)) throw new Error('An absolute private profile directory is required');
  await fs.mkdir(appOwnedBase, { recursive: true, mode: 0o700 });
  const baseInfo = await fs.lstat(appOwnedBase);
  if (!baseInfo.isDirectory() || baseInfo.isSymbolicLink()) throw new Error('Invalid private profile directory');
  const base = await fs.realpath(appOwnedBase);
  const geminiDir = path.join(base, 'gemini');
  const cliDir = path.join(geminiDir, 'antigravity-cli');
  for (const dir of [geminiDir, cliDir]) {
    await fs.mkdir(dir, { mode: 0o700 }).catch((error: NodeJS.ErrnoException) => {
      if (error.code !== 'EEXIST') throw error;
    });
    const info = await fs.lstat(dir);
    if (!info.isDirectory() || info.isSymbolicLink()) throw new Error('Invalid private profile directory');
  }
  const settings = path.join(cliDir, 'settings.json');
  try { await fs.writeFile(settings, POLICY, { flag: 'wx', encoding: 'utf8', mode: 0o600 }); }
  catch (error: unknown) {
    if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error;
    const info = await fs.lstat(settings);
    if (!info.isFile() || info.isSymbolicLink() || info.size > 8192 || await fs.readFile(settings, 'utf8') !== POLICY)
      throw new Error('Private agent permission settings were changed');
  }
  return geminiDir;
}
