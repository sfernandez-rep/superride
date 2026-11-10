// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
import { createHash, randomBytes } from 'node:crypto';
import { previewTextEdit, TextEdit } from './text-proposal';

/**
 * Edit proposals for Chat IA (phase 3). A model may only *propose* changes:
 * exact-text replacements (each old text must occur exactly once in the base)
 * or a full new content. Nothing here writes files. The renderer shows the diff
 * and applies an accepted proposal through the editor (undoable), after checking
 * that the document still equals the base this proposal was computed from.
 */
export interface DiffLine { type: ' ' | '-' | '+'; text: string }
export interface DiffHunk { oldStart: number; oldLines: number; newStart: number; newLines: number; lines: DiffLine[] }
export interface EditProposal {
  id: string;
  /** Path relative to the project (or the document name in file mode), for display. */
  path: string;
  /** Path the IDE uses to open the file (aliased, ~/...), or empty for an untitled active document. */
  idePath: string;
  summary: string;
  original: string;
  proposed: string;
  baseHash: string;
  source: 'disk' | 'editor' | 'editor-unsaved';
  added: number;
  removed: number;
  hunks: DiffHunk[];
}
export interface EditRequest { old_text?: unknown; new_text?: unknown }

const MAX_CONTENT = 512 * 1024;
const MAX_EDITS = 50;
const CONTEXT = 3;

export class ProposalError extends Error {}

export function hashText(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

function count(haystack: string, needle: string): number {
  let n = 0;
  for (let at = haystack.indexOf(needle); at >= 0; at = haystack.indexOf(needle, at + needle.length)) n++;
  return n;
}

/** Applies exact-text edits to the base; each old text must occur exactly once and edits must not overlap. */
export function applyEdits(base: string, edits: readonly EditRequest[]): string {
  if (!edits.length || edits.length > MAX_EDITS) throw new ProposalError(`Give 1 to ${MAX_EDITS} edits.`);
  // the editor and the model may disagree on line endings; match on the document's own
  const crlf = base.includes('\r\n');
  const textEdits: TextEdit[] = edits.map((edit, i) => {
    if (typeof edit.old_text !== 'string' || !edit.old_text || typeof edit.new_text !== 'string')
      throw new ProposalError(`Edit ${i + 1}: old_text (non-empty) and new_text are required.`);
    const oldText = crlf ? edit.old_text.replace(/\r?\n/g, '\r\n') : edit.old_text;
    const newText = crlf ? edit.new_text.replace(/\r?\n/g, '\r\n') : edit.new_text;
    const occurrences = count(base, oldText);
    if (occurrences !== 1)
      throw new ProposalError(`Edit ${i + 1}: old_text occurs ${occurrences} times; it must match the current file exactly once.`);
    const start = base.indexOf(oldText);
    return { start, end: start + oldText.length, expected: oldText, replacement: newText };
  });
  try { return previewTextEdit(base, textEdits).after; }
  catch { throw new ProposalError('The edits overlap or split a character.'); }
}

function splitLines(text: string): string[] {
  const lines = text.split(/\r?\n/);
  if (lines.length > 1 && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

/** Line diff (LCS) grouped in hunks with 3 lines of context; large inputs fall back to one hunk. */
export function diffLines(before: string, after: string): { hunks: DiffHunk[]; added: number; removed: number } {
  const a = splitLines(before), b = splitLines(after);
  let prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] === b[prefix]) prefix++;
  let suffix = 0;
  const same = (k: number) => a[a.length - 1 - k] === b[b.length - 1 - k];
  while (suffix < a.length - prefix && suffix < b.length - prefix && same(suffix)) suffix++;
  const midA = a.slice(prefix, a.length - suffix), midB = b.slice(prefix, b.length - suffix);
  const ops: DiffLine[] = a.slice(0, prefix).map(text => ({ type: ' ' as const, text }));
  if (midA.length * midB.length <= 4000000) {
    const n = midA.length, m = midB.length;
    const table = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
    for (let i = n - 1; i >= 0; i--)
      for (let j = m - 1; j >= 0; j--)
        table[i][j] = midA[i] === midB[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
    let i = 0, j = 0;
    while (i < n || j < m) {
      if (i < n && j < m && midA[i] === midB[j]) { ops.push({ type: ' ', text: midA[i] }); i++; j++; }
      else if (i < n && (j === m || table[i + 1][j] >= table[i][j + 1])) ops.push({ type: '-', text: midA[i++] });
      else ops.push({ type: '+', text: midB[j++] });
    }
  } else {
    for (const text of midA) ops.push({ type: '-', text });
    for (const text of midB) ops.push({ type: '+', text });
  }
  for (const text of a.slice(a.length - suffix)) ops.push({ type: ' ', text });

  const hunks: DiffHunk[] = [];
  let added = 0, removed = 0, oldLine = 1, newLine = 1;
  let current: DiffHunk | null = null;
  let trailing = 0;
  for (let k = 0; k < ops.length; k++) {
    const op = ops[k];
    if (op.type !== ' ') {
      if (!current) {
        const from = Math.max(0, k - CONTEXT);
        const lead = ops.slice(from, k);
        current = { oldStart: oldLine - lead.length, newStart: newLine - lead.length, oldLines: lead.length,
          newLines: lead.length, lines: [...lead] };
        hunks.push(current);
      }
      current.lines.push(op);
      if (op.type === '-') { current.oldLines++; removed++; oldLine++; } else { current.newLines++; added++; newLine++; }
      trailing = 0;
      continue;
    }
    if (current) {
      // keep up to 2 * CONTEXT unchanged lines inside a hunk, so nearby changes merge
      const nextChange = ops.slice(k, k + 2 * CONTEXT + 1).findIndex(o => o.type !== ' ');
      if (trailing < CONTEXT || (nextChange > 0 && nextChange <= 2 * CONTEXT)) {
        current.lines.push(op); current.oldLines++; current.newLines++; trailing++;
      } else current = null;
    }
    oldLine++; newLine++;
  }
  return { hunks, added, removed };
}

export function makeProposal(input: { path: string; idePath: string; summary: string; original: string;
  proposed: string; source: EditProposal['source'] }): EditProposal {
  if (input.original.length > MAX_CONTENT || input.proposed.length > MAX_CONTENT) throw new ProposalError('The file is too large to edit here.');
  if (input.proposed === input.original) throw new ProposalError('The proposal does not change the file.');
  const { hunks, added, removed } = diffLines(input.original, input.proposed);
  return { id: randomBytes(8).toString('hex'), path: input.path, idePath: input.idePath, summary: input.summary.slice(0, 500),
    original: input.original, proposed: input.proposed, baseHash: hashText(input.original), source: input.source,
    added, removed, hunks };
}
