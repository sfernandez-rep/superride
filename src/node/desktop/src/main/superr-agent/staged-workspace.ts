// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { createHash } from 'node:crypto';
import { ProjectReader } from './project-reader';

/**
 * A disposable, explicitly populated copy. It is not an OS sandbox: a caller
 * must also enforce the agent's access and permission policy before launch.
 */
export class StagedWorkspace {
  private sealed = false;
  private pendingIncludes = 0;
  private removed = false;
  private readonly originals = new Map<string, { text: string; sha256: string }>();
  private constructor(private readonly base: string, readonly directory: string) {}

  static async create(appOwnedBase: string): Promise<StagedWorkspace> {
    if (!path.isAbsolute(appOwnedBase)) throw new Error('An absolute private staging directory is required');
    await fs.mkdir(appOwnedBase, { recursive: true, mode: 0o700 });
    const info = await fs.lstat(appOwnedBase);
    if (!info.isDirectory() || info.isSymbolicLink()) throw new Error('Invalid staging directory');
    const base = await fs.realpath(appOwnedBase);
    const directory = await fs.mkdtemp(path.join(base, 'superr-session-'));
    return new StagedWorkspace(base, directory);
  }

  /** Must be called before launching an agent; never reads an entire project. */
  async include(reader: ProjectReader, relative: string): Promise<void> {
    if (this.sealed || this.removed) throw new Error('The agent workspace is already sealed');
    this.pendingIncludes++;
    try {
      const text = await reader.read(relative); // validates each component and extension
      const parts = relative.split(/[\\/]+/);
      const canonicalName = parts.join('/');
      if (this.originals.has(canonicalName)) throw new Error('File is already included');
      const destination = path.join(this.directory, ...parts);
      const relativeDestination = path.relative(this.directory, destination);
      if (!relativeDestination || relativeDestination === '..' || relativeDestination.startsWith(`..${path.sep}`) || path.isAbsolute(relativeDestination))
        throw new Error('Invalid staged path');
      await fs.mkdir(path.dirname(destination), { recursive: true, mode: 0o700 });
      await fs.writeFile(destination, text, { encoding: 'utf8', flag: 'wx', mode: 0o600 });
      this.originals.set(canonicalName, { text, sha256: createHash('sha256').update(text, 'utf8').digest('hex') });
    } finally { this.pendingIncludes--; }
  }

  seal(): void {
    if (this.removed) throw new Error('The agent workspace was removed');
    if (this.pendingIncludes) throw new Error('Wait for selected files to finish staging');
    this.sealed = true;
  }

  /** The caller must compare against the live editor/disk before approving edits. */
  original(relative: string): { text: string; sha256: string } | undefined {
    const value = this.originals.get(relative.replaceAll('\\', '/'));
    return value ? { ...value } : undefined;
  }

  async cleanup(): Promise<void> {
    if (this.removed) return;
    if (this.pendingIncludes) throw new Error('Wait for selected files to finish staging');
    const relative = path.relative(this.base, this.directory);
    if (!relative || relative.includes(path.sep) || !relative.startsWith('superr-session-'))
      throw new Error('Invalid staging cleanup target');
    let info;
    try { info = await fs.lstat(this.directory); }
    catch (error: unknown) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') { this.removed = true; return; } throw error; }
    if (!info.isDirectory() || info.isSymbolicLink() || await fs.realpath(this.directory) !== this.directory)
      throw new Error('Invalid staging cleanup target');
    await fs.rm(this.directory, { recursive: true, force: true });
    this.removed = true;
    this.originals.clear();
  }
}
