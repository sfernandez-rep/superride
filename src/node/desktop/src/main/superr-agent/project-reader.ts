// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import * as fs from 'node:fs/promises';
import { constants } from 'node:fs';
import * as path from 'node:path';
import { TextDecoder } from 'node:util';

const MAX_FILE_BYTES = 1024 * 1024;
const EXTENSIONS = new Set(['.r', '.rmd', '.qmd', '.csv', '.tsv', '.txt']);
const DATA_EXTENSIONS = new Set(['.rds', '.rdata']);
const HIDDEN = new Set(['.git', '.svn', '.hg', '.ssh', '.aws', '.config', '.gnupg',
  '.renviron', '.rprofile', '.rhistory', '.env', '.cache', '.rproj.user', '.quarto',
  'node_modules', 'renv', 'packrat', 'build', 'dist', 'vendor', '_site']);

function inside(root: string, candidate: string): boolean {
  const relative = path.relative(root, candidate);
  return !!relative && relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

function allowedPart(part: string): boolean {
  const lower = part.toLowerCase();
  return !HIDDEN.has(lower) && !lower.startsWith('.env.') && !lower.startsWith('.renviron.') &&
    !lower.includes('credential') && !lower.includes('secret') &&
    !lower.endsWith('.key') && !lower.endsWith('.pem') && !lower.endsWith('.p12');
}

/** Bounded, explicitly selected project files only; does not sandbox agent processes. */
export class ProjectReader {
  private constructor(private readonly root: string) {}

  static async open(root: string): Promise<ProjectReader> {
    if (!path.isAbsolute(root)) throw new Error('An absolute project directory is required');
    const realRoot = await fs.realpath(root);
    if (!(await fs.stat(realRoot)).isDirectory()) throw new Error('Project root is not a directory');
    return new ProjectReader(realRoot);
  }

  /** Enumerates names only. Binary R files are identified but never unserialized. */
  async list(): Promise<{ files: string[]; truncated: boolean }> {
    const files: string[] = [];
    const directories = [''];
    let visited = 0;
    let scanned = 0;
    let truncated = false;
    while (directories.length) {
      if (++visited > 1000 || files.length >= 2000) { truncated = true; break; }
      const relative = directories.shift()!;
      const directory = path.join(this.root, relative);
      const stat = await fs.lstat(directory);
      if (stat.isSymbolicLink() || !stat.isDirectory()) continue;
      const real = await fs.realpath(directory);
      if (real !== this.root && !inside(this.root, real)) continue;
      const entries = await fs.opendir(directory);
      for await (const entry of entries) {
        if (++scanned > 20000) { truncated = true; directories.length = 0; break; }
        if (!allowedPart(entry.name) || entry.isSymbolicLink()) continue;
        const name = relative ? path.join(relative, entry.name) : entry.name;
        if (entry.isDirectory()) directories.push(name);
        else if (entry.isFile() && (EXTENSIONS.has(path.extname(name).toLowerCase()) ||
                                   DATA_EXTENSIONS.has(path.extname(name).toLowerCase()))) {
          if (files.length === 2000) { truncated = true; break; }
          files.push(name.split(path.sep).join('/'));
        }
      }
    }
    files.sort();
    return { files, truncated };
  }

  /** Search locally; the caller chooses whether to disclose returned snippets. */
  async search(query: string): Promise<{ matches: Array<{ file: string; line: number; snippet: string }>; truncated: boolean }> {
    if (!query.trim() || query.length > 200) throw new Error('Invalid search term');
    const listing = await this.list();
    const matches: Array<{ file: string; line: number; snippet: string }> = [];
    const term = query.toLowerCase();
    for (const file of listing.files) {
      if (!EXTENSIONS.has(path.extname(file).toLowerCase())) continue;
      let content: string;
      try { content = await this.read(file); } catch { continue; }
      const lines = content.split(/\r\n|\n|\r/);
      for (let i = 0; i < lines.length; i++) {
        if (!lines[i].toLowerCase().includes(term)) continue;
        matches.push({ file, line: i + 1, snippet: lines[i].slice(0, 300) });
        if (matches.length === 100) return { matches, truncated: true };
      }
    }
    return { matches, truncated: listing.truncated };
  }

  async read(relative: string): Promise<string> {
    if (!relative || path.isAbsolute(relative) || relative.includes('\0')) throw new Error('Invalid project path');
    const parts = relative.split(/[\\/]+/);
    if (parts.some(part => !part || part === '.' || part === '..' || !allowedPart(part)))
      throw new Error('Project path is not allowed');
    const candidate = path.join(this.root, ...parts);
    if (!inside(this.root, candidate) || !EXTENSIONS.has(path.extname(candidate).toLowerCase()))
      throw new Error('Project path is not allowed');

    // Reject symlinks/junctions anywhere under the root, including the leaf.
    let current = this.root;
    for (const part of parts) {
      current = path.join(current, part);
      const info = await fs.lstat(current);
      if (info.isSymbolicLink()) throw new Error('Project links are not allowed');
    }
    const realPath = await fs.realpath(candidate);
    if (!inside(this.root, realPath)) throw new Error('Project path is not allowed');
    const flags = constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0);
    const handle = await fs.open(realPath, flags);
    try {
      const info = await handle.stat();
      if (!info.isFile() || info.size > MAX_FILE_BYTES) throw new Error('File is not a supported size or type');
      // Read at most the advertised limit, even if the file grows during the read.
      const bytes = Buffer.alloc(MAX_FILE_BYTES + 1);
      let bytesRead = 0;
      while (bytesRead < bytes.length) {
        const result = await handle.read(bytes, bytesRead, bytes.length - bytesRead, bytesRead);
        if (!result.bytesRead) break;
        bytesRead += result.bytesRead;
      }
      if (bytesRead > MAX_FILE_BYTES || bytes.subarray(0, bytesRead).includes(0))
        throw new Error('File is not a supported text file');
      return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes.subarray(0, bytesRead));
    } finally {
      await handle.close();
    }
  }
}
