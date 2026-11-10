// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import * as fs from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import { ProjectReader } from './project-reader';
import { applyEdits, EditProposal, EditRequest, makeProposal, ProposalError } from './edit-proposal';

/**
 * Provider-neutral, read-only project context for Chat IA. The renderer sends
 * what the IDE shows (project directory, active document with unsaved edits,
 * selection, other open documents); this module decides what may be disclosed.
 * Files are read only through ProjectReader (allowed extensions, no secrets by
 * name, no links, size limits, canonical paths inside the project). Nothing
 * here writes files or runs commands. It is not an OS sandbox: it only controls
 * what SuperR itself reads and sends.
 *
 * propose_file_edit (phase 3) creates a reviewable proposal from the current
 * editor or disk content; it never writes. The renderer applies an accepted
 * proposal through the editor after checking the document is unchanged.
 */
export type ContextMode = 'general' | 'file' | 'project';
export interface ContextDocument { path?: string; name: string; content: string; dirty: boolean; selection?: string }
export interface ChatContext {
  mode: ContextMode; projectRoot?: string; active?: ContextDocument; open?: ContextDocument[];
}
/** A file whose content was actually disclosed, and from where. */
export interface DisclosedFile { path: string; source: 'editor' | 'editor-unsaved' | 'disk'; truncated?: boolean }
export interface ToolDeclaration { name: string; description: string; parameters: Record<string, unknown> }
export interface ToolResult { response: Record<string, unknown>; files: DisclosedFile[]; proposal?: EditProposal }
export interface ContextOptions {
  aliasPath?: (absolute: string) => string;
  /** Personal folders besides the OS home (for example RStudio's ~) that must never be a project. */
  homes?: string[];
}

export class ContextError extends Error {
  constructor(readonly code: 'no_project' | 'home_folder' | 'invalid_project' | 'no_document' | 'invalid_context') {
    super(`Context: ${code}`);
  }
}

const MAX_DOCUMENT_CHARS = 1024 * 1024;
const MAX_FILE_CHARS = 60000;
const MAX_CALL_CHARS = 180000;
const MAX_DATA_BYTES = 32 * 1024;
const MAX_OPEN_DOCUMENTS = 30;
const MAX_INDEX_FILES = 300;
const DATA = new Set(['.csv', '.tsv', '.txt']);
const EDITABLE = new Set(['.r', '.rmd', '.qmd']);
const MAX_PROPOSALS = 10;

type Obj = Record<string, unknown>;
function obj(value: unknown): value is Obj { return typeof value === 'object' && value !== null && !Array.isArray(value); }
function str(value: unknown, max: number): value is string { return typeof value === 'string' && value.length <= max; }

/** Validates the renderer's description; throws ContextError on anything malformed. */
export function parseContext(value: unknown): ChatContext {
  if (value === undefined || value === null) return { mode: 'general' };
  if (!obj(value) || (value.mode !== 'general' && value.mode !== 'file' && value.mode !== 'project'))
    throw new ContextError('invalid_context');
  const document = (d: unknown): ContextDocument => {
    if (!obj(d) || !str(d.name, 1000) || !str(d.content, MAX_DOCUMENT_CHARS) || typeof d.dirty !== 'boolean' ||
        (d.path !== undefined && !str(d.path, 4096)) ||
        (d.selection !== undefined && !str(d.selection, MAX_DOCUMENT_CHARS)))
      throw new ContextError('invalid_context');
    return { name: d.name, content: d.content, dirty: d.dirty, ...(d.path ? { path: d.path } : {}),
      ...(d.selection ? { selection: d.selection } : {}) };
  };
  const context: ChatContext = { mode: value.mode };
  if (value.projectRoot !== undefined && value.projectRoot !== '') {
    if (!str(value.projectRoot, 4096)) throw new ContextError('invalid_context');
    context.projectRoot = value.projectRoot;
  }
  if (value.active !== undefined && value.active !== null) context.active = document(value.active);
  if (value.open !== undefined) {
    if (!Array.isArray(value.open) || value.open.length > MAX_OPEN_DOCUMENTS) throw new ContextError('invalid_context');
    context.open = value.open.map(document);
  }
  return context;
}

/** True when `inner` is `outer` or inside it (false across drives). */
function within(outer: string, inner: string): boolean {
  const relative = path.relative(outer, inner);
  return relative === '' || (!path.isAbsolute(relative) && relative.split(path.sep)[0] !== '..');
}

/**
 * A project directory: absolute, a real directory with an .Rproj file, never a
 * drive root, a personal folder, or a folder that contains one.
 */
async function checkedRoot(root: string, extraHomes: readonly string[]): Promise<string> {
  if (!path.isAbsolute(root)) throw new ContextError('invalid_project');
  let real: string;
  try { real = await fs.realpath(root); } catch { throw new ContextError('invalid_project'); }
  if (path.parse(real).root === real) throw new ContextError('invalid_project');
  for (const candidate of [os.homedir(), ...extraHomes]) {
    if (!candidate || !path.isAbsolute(candidate)) continue;
    const home = await fs.realpath(candidate).catch(() => path.resolve(candidate));
    if (within(real, home)) throw new ContextError('home_folder');
  }
  const entries = await fs.readdir(real, { withFileTypes: true }).catch(() => { throw new ContextError('invalid_project'); });
  if (!entries.some(entry => entry.isFile() && entry.name.toLowerCase().endsWith('.rproj'))) throw new ContextError('invalid_project');
  return real;
}

/** The document with its path in canonical form (its folder's, if the file itself does not exist). */
async function canonicalDocument(document: ContextDocument): Promise<ContextDocument> {
  if (!document.path || !path.isAbsolute(document.path)) return document;
  const file = document.path;
  const real = await fs.realpath(file).catch(() =>
    fs.realpath(path.dirname(file)).then(dir => path.join(dir, path.basename(file))).catch(() => file));
  return { ...document, path: real };
}

function cut(text: string, max: number): { text: string; truncated: boolean } {
  if (text.length <= max) return { text, truncated: false };
  const end = text.lastIndexOf('\n', max);
  return { text: text.slice(0, end > max / 2 ? end : max), truncated: true };
}

function fence(name: string, content: string): string {
  let ticks = '```';
  while (content.includes(ticks)) ticks += '`';
  const ext = path.extname(name).toLowerCase();
  const language = ext === '.r' ? 'r' : ext === '.rmd' || ext === '.qmd' ? 'markdown' : ext === '.csv' || ext === '.tsv' ? 'csv' : '';
  return `${ticks}${language}\n${content}\n${ticks}`;
}

export class ProjectContext {
  private readonly unsaved = new Map<string, ContextDocument>();
  private readonly disclosed = new Map<string, DisclosedFile>();
  private proposals = 0;
  private constructor(readonly context: ChatContext, private readonly reader: ProjectReader | null,
    private readonly projectName: string, private readonly options: ContextOptions) {}

  /** Opens the context. Project mode requires a valid project; file mode an active document. */
  static async open(context: ChatContext, options: ContextOptions = {}): Promise<ProjectContext> {
    if (context.mode === 'file' && !context.active) throw new ContextError('no_document');
    let reader: ProjectReader | null = null;
    if (context.mode === 'project') {
      if (!context.projectRoot) throw new ContextError('no_project');
      reader = await ProjectReader.open(await checkedRoot(context.projectRoot, options.homes ?? []));
      // The project root is canonical; compare documents in the same form (links,
      // junctions and Windows 8.3 short names would otherwise hide unsaved text).
      context = { ...context, ...(context.active ? { active: await canonicalDocument(context.active) } : {}),
        ...(context.open ? { open: await Promise.all(context.open.map(canonicalDocument)) } : {}) };
    }
    const result = new ProjectContext(context, reader, reader ? path.basename(reader.root) : '', options);
    if (reader)
      for (const document of [...(context.open ?? []), ...(context.active ? [context.active] : [])]) {
        const relative = document.path ? result.relativeOf(document.path) : null;
        if (relative && document.dirty) result.unsaved.set(relative.toLowerCase(), document);
      }
    return result;
  }

  get mode(): ContextMode { return this.context.mode; }
  /** Every file disclosed so far in this turn. */
  get files(): DisclosedFile[] { return [...this.disclosed.values()]; }

  /** Text to place before the user's message (file mode), and what it discloses. */
  attachment(): string {
    const active = this.context.active;
    if (this.context.mode !== 'file' || !active) return '';
    const name = active.path ? path.basename(active.path) : active.name;
    const { text, truncated } = cut(active.content, MAX_FILE_CHARS * 2);
    this.disclose({ path: name, source: active.dirty ? 'editor-unsaved' : 'editor', truncated });
    let result = `[SuperR attached the active editor document "${name}"${active.dirty ? ' (with unsaved changes)' : ''}` +
      `${truncated ? ', truncated' : ''}]\n${fence(name, text)}\n`;
    if (active.selection)
      result += `[Selected code in that document]\n${fence(name, cut(active.selection, MAX_FILE_CHARS).text)}\n`;
    return result + '[User message]\n';
  }

  /** System instruction for the model; in project mode it carries the file index. */
  async instruction(): Promise<string> {
    const base = 'You are Chat IA inside SuperR, an IDE for R (an independent fork of RStudio) used for scientific ' +
      'analysis, ggplot2 and fisheries work with TropFishR. Answer in the language of the user\'s message. ' +
      'You cannot run code, install packages or modify files. Put R code in fenced ```r blocks. ' +
      'Never claim to have read, run or checked a file unless its content was given to you in this conversation.';
    const editing = ' To change a file, call propose_file_edit with exact old_text copied from the file as given to ' +
      'you (each must occur exactly once) and the new_text; prefer small edits. The user reviews a diff in SuperR and ' +
      'accepts or rejects it: never say a change was applied or saved.';
    if (this.context.mode === 'file')
      return `${base} The user attached the active document from the editor; base file-specific statements on it ` +
        `only.${editing} In this mode only the attached document can be changed.`;
    if (this.context.mode !== 'project' || !this.reader) return base;
    const listing = await this.reader.list();
    const entries: string[] = [];
    for (const file of listing.files.slice(0, MAX_INDEX_FILES)) {
      const info = await this.reader.info(file).catch(() => null);
      if (info) entries.push(`${file} (${info.bytes} bytes${info.kind === 'r-binary' ? ', binary R data' : ''}` +
        `${this.unsaved.has(file.toLowerCase()) ? ', unsaved changes in the editor' : ''})`);
    }
    const truncated = listing.truncated || listing.files.length > MAX_INDEX_FILES;
    return `${base}\n\nProject mode: the user authorised read-only access to the R project "${this.projectName}". ` +
      'SuperR runs the provided functions for you; nothing else on the computer is reachable. File index' +
      `${truncated ? ' (truncated)' : ''}:\n${entries.join('\n') || '(no readable files)'}\n\n` +
      'Read what you need with read_project_files, several paths in one call: every extra function round uses one ' +
      'request of the user\'s small free quota, so plan your reads and use at most 3 rounds. ' +
      'Only state what the files you actually read show; say which files you did not read.' +
      `${editing} Read a file before proposing changes to it; only .R, .Rmd and .qmd files can be changed.`;
  }

  /** Function declarations offered to the model (project mode only). */
  tools(): ToolDeclaration[] {
    const propose: ToolDeclaration = { name: 'propose_file_edit',
      description: 'Proposes a change to one script for the user to review (nothing is written). Use exact-text ' +
        'replacements; each old_text must occur exactly once in the current file.',
      parameters: { type: 'object', required: ['path', 'edits', 'summary'], properties: {
        path: { type: 'string', description: 'Relative path in the project, or the attached document name' },
        summary: { type: 'string', description: 'One sentence for the user: what the change does' },
        edits: { type: 'array', items: { type: 'object', required: ['old_text', 'new_text'], properties: {
          old_text: { type: 'string' }, new_text: { type: 'string' } } } } } } };
    if (this.context.mode === 'file') return [propose];
    if (this.context.mode !== 'project') return [];
    const none = { type: 'object', properties: {} };
    return [propose,
      { name: 'get_project_context', parameters: none,
        description: 'Project name, number of readable files, R packages used (from library/require/pkg:: calls), the ' +
          'active document and documents with unsaved changes.' },
      { name: 'list_project_files', description: 'Readable project files with their size, optionally filtered by a ' +
          'case-insensitive substring of the path.',
      parameters: { type: 'object', properties: { contains: { type: 'string', description: 'Substring of the path' } } } },
      { name: 'read_project_files', description: 'Reads up to 8 project files by their relative paths. Unsaved editor ' +
          'changes take priority over the disk. Large files and data files are truncated; binary R data (.rds, .RData) ' +
          'is never read.',
      parameters: { type: 'object', required: ['paths'], properties: {
        paths: { type: 'array', items: { type: 'string' }, description: 'Relative paths from the index, at most 8' } } } },
      { name: 'search_project_files', description: 'Case-insensitive text search in the project scripts and text files; ' +
          'returns file, line number and the line.',
      parameters: { type: 'object', required: ['query'], properties: { query: { type: 'string' } } } },
      { name: 'get_active_document', description: 'The document active in the editor, including unsaved changes.',
        parameters: none },
      { name: 'get_selected_code', description: 'The code selected in the active editor, if any.', parameters: none },
    ];
  }

  /** Runs one function call. Errors are returned to the model, never thrown. */
  async call(name: string, args: Obj): Promise<ToolResult> {
    const before = this.disclosed.size;
    const files = () => [...this.disclosed.values()].slice(before);
    try {
      if (name === 'propose_file_edit') return this.propose(args);
      if (!this.reader) return { response: { error: 'Project access is not enabled for this message.' }, files: [] };
      switch (name) {
        case 'get_project_context': return { response: await this.projectSummary(), files: [] };
        case 'list_project_files': {
          const contains = typeof args.contains === 'string' ? args.contains.toLowerCase().slice(0, 200) : '';
          const listing = await this.reader.list();
          const selected = listing.files
            .filter(file => !contains || file.toLowerCase().includes(contains)).slice(0, 500);
          const result = [];
          for (const file of selected) {
            const info = await this.reader.info(file).catch(() => null);
            if (info) result.push({ path: file, bytes: info.bytes, kind: info.kind });
          }
          return { response: { files: result, truncated: listing.truncated || selected.length === 500 }, files: [] };
        }
        case 'read_project_files': {
          const paths = Array.isArray(args.paths) ? args.paths.filter((p): p is string => typeof p === 'string').slice(0, 8) : [];
          if (!paths.length) return { response: { error: 'Give 1 to 8 relative paths.' }, files: [] };
          let budget = MAX_CALL_CHARS;
          const results = [];
          for (const file of paths) {
            const result = await this.readOne(file, Math.min(MAX_FILE_CHARS, budget));
            if (typeof result.content === 'string') budget -= result.content.length;
            results.push(result);
          }
          return { response: { files: results }, files: files() };
        }
        case 'search_project_files': {
          const query = typeof args.query === 'string' ? args.query : '';
          if (!query.trim()) return { response: { error: 'A search term is required.' }, files: [] };
          const found = await this.reader.search(query.slice(0, 200));
          for (const match of found.matches) this.disclose({ path: match.file, source: 'disk', truncated: true });
          return { response: { matches: found.matches, truncated: found.truncated }, files: files() };
        }
        case 'get_active_document': {
          const active = this.context.active;
          if (!active) return { response: { error: 'No document is active in the editor.' }, files: [] };
          const relative = active.path ? this.relativeOf(active.path) : null;
          if (!relative) return { response: { error: 'The active document is not a saved file inside the authorised project.' }, files: [] };
          const { text, truncated } = cut(active.content, MAX_FILE_CHARS);
          this.disclose({ path: relative, source: active.dirty ? 'editor-unsaved' : 'editor', truncated });
          return { response: { path: relative, unsaved_changes: active.dirty, content: text, truncated },
            files: files() };
        }
        case 'get_selected_code': {
          const active = this.context.active;
          if (!active?.selection) return { response: { selection: '', note: 'Nothing is selected.' }, files: [] };
          const relative = active.path ? this.relativeOf(active.path) : null;
          if (!relative) return { response: { error: 'The active document is not a saved file inside the authorised project.' }, files: [] };
          this.disclose({ path: relative, source: active.dirty ? 'editor-unsaved' : 'editor', truncated: true });
          return { response: { path: relative, selection: cut(active.selection, MAX_FILE_CHARS).text },
            files: files() };
        }
        default: return { response: { error: `Unknown function ${name}.` }, files: [] };
      }
    } catch {
      return { response: { error: 'The request could not be completed.' }, files: files() };
    }
  }

  /** Builds a proposal from the current text (unsaved editor changes first). Never writes. */
  private async propose(args: Obj): Promise<ToolResult> {
    const refuse = (error: string): ToolResult => ({ response: { error }, files: [] });
    if (this.proposals >= MAX_PROPOSALS) return refuse(`At most ${MAX_PROPOSALS} proposals per message.`);
    const requested = typeof args.path === 'string' ? args.path.replace(/\\/g, '/').replace(/^\.\//, '') : '';
    const edits = Array.isArray(args.edits) ? args.edits as EditRequest[] : [];
    const summary = typeof args.summary === 'string' ? args.summary : '';
    if (!requested) return refuse('A path is required.');
    let base: string, source: EditProposal['source'], display: string, absolute: string | undefined;
    const active = this.context.active;
    if (this.context.mode === 'file') {
      const name = active ? (active.path ? path.basename(active.path) : active.name) : '';
      if (!active || (requested !== name && requested !== active.name && requested !== active.path))
        return refuse('In this mode only the attached document can be changed.');
      base = active.content; source = active.dirty ? 'editor-unsaved' : 'editor'; display = name; absolute = active.path;
    } else if (this.reader) {
      if (!EDITABLE.has(path.extname(requested).toLowerCase())) return refuse('Only .R, .Rmd and .qmd files can be changed.');
      const unsaved = this.unsaved.get(requested.toLowerCase());
      const activeRelative = active?.path ? this.relativeOf(active.path) : null;
      if (unsaved) { base = unsaved.content; source = 'editor-unsaved'; }
      else if (active && activeRelative && activeRelative.toLowerCase() === requested.toLowerCase()) { base = active.content; source = 'editor'; }
      else {
        try { base = await this.reader.read(requested); }
        catch { return refuse('Not changeable: missing, outside the project, a link, sensitive by name, or not UTF-8 text.'); }
        source = 'disk';
      }
      display = requested;
      absolute = path.join(this.reader.root, ...requested.split('/'));
    } else return refuse('File changes are not enabled for this message.');
    let proposed: string;
    try { proposed = applyEdits(base, edits); }
    catch (error: unknown) { return refuse(error instanceof ProposalError ? error.message : 'The edits could not be applied.'); }
    let proposal: EditProposal;
    try {
      proposal = makeProposal({ path: display, idePath: absolute ? (this.options.aliasPath?.(absolute) ?? absolute) : '',
        summary, original: base, proposed, source });
    } catch (error: unknown) { return refuse(error instanceof ProposalError ? error.message : 'The proposal is not valid.'); }
    this.proposals++;
    return { response: { status: 'proposed', path: display, added_lines: proposal.added, removed_lines: proposal.removed,
      note: 'Shown to the user as a diff to accept or reject. It has NOT been applied or saved.' }, files: [], proposal };
  }

  private async readOne(file: string, budget: number): Promise<Obj> {
    if (!this.reader) return { path: file, error: 'No project' };
    const relative = file.replace(/\\/g, '/').replace(/^\.\//, '');
    const unsaved = this.unsaved.get(relative.toLowerCase());
    if (unsaved) {
      const { text, truncated } = cut(unsaved.content, budget);
      this.disclose({ path: relative, source: 'editor-unsaved', truncated });
      return { path: relative, source: 'editor (unsaved changes)', content: text, truncated };
    }
    try {
      const info = await this.reader.info(relative);
      if (info.kind === 'r-binary')
        return { path: relative, bytes: info.bytes, note: 'Binary R data file; SuperR does not read it. Ask the user ' +
          'to describe it, or suggest R code (readRDS/load, str) that the user can run.' };
      if (DATA.has(path.extname(relative).toLowerCase()) && info.bytes > MAX_DATA_BYTES) {
        const head = await this.reader.readHead(relative, MAX_DATA_BYTES);
        const { text } = cut(head.text, budget);
        this.disclose({ path: relative, source: 'disk', truncated: true });
        return { path: relative, bytes: info.bytes, content: text, truncated: true,
          note: 'Only the first lines of this data file were read.' };
      }
      const { text, truncated } = cut(await this.reader.read(relative), budget);
      this.disclose({ path: relative, source: 'disk', truncated });
      return { path: relative, content: text, truncated };
    } catch {
      return { path: relative, error: 'Not readable: missing, outside the project, a link, sensitive by name, ' +
        'not UTF-8 text, or too large.' };
    }
  }

  private async projectSummary(): Promise<Obj> {
    if (!this.reader) return {};
    const listing = await this.reader.list();
    const packages = new Set<string>();
    for (const file of listing.files.filter(f => /\.(r|rmd|qmd)$/i.test(f)).slice(0, 200)) {
      let content = this.unsaved.get(file.toLowerCase())?.content;
      if (content === undefined) content = await this.reader.read(file).catch(() => '');
      const calls = /\b(?:library|require|requireNamespace)\(\s*["']?([A-Za-z][A-Za-z0-9.]*)["']?/g;
      for (const match of content.matchAll(calls)) packages.add(match[1]);
      for (const match of content.matchAll(/\b([A-Za-z][A-Za-z0-9.]*):::?[A-Za-z._]/g)) packages.add(match[1]);
    }
    const active = this.context.active;
    return { project: this.projectName, readable_files: listing.files.length, truncated: listing.truncated,
      packages: [...packages].sort(),
      active_document: active ? (active.path ? this.relativeOf(active.path) ?? active.name : active.name) : null,
      unsaved_documents: [...this.unsaved.keys()] };
  }

  private relativeOf(file: string): string | null {
    if (!this.reader || !path.isAbsolute(file)) return null;
    const relative = path.relative(this.reader.root, path.resolve(file));
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) return null;
    return relative.split(path.sep).join('/');
  }

  private disclose(file: DisclosedFile): void {
    const key = file.path.toLowerCase();
    const known = this.disclosed.get(key);
    if (!known || (known.truncated && !file.truncated)) this.disclosed.set(key, file);
  }
}
