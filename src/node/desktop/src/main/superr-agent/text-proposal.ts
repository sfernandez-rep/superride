// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only

/** A text edit uses UTF-16 offsets, as in JavaScript and the Ace editor. */
export interface TextEdit { start: number; end: number; expected: string; replacement: string }
export interface TextPreview { before: string; after: string; edits: readonly TextEdit[] }
const previews = new WeakSet<object>();

/**
 * Produces an in-memory preview. It performs no IO and cannot modify an editor.
 * The integration must validate the target path and preserve its encoding.
 */
export function previewTextEdit(before: string, edits: readonly TextEdit[]): TextPreview {
  if (!edits.length || edits.length > 1000) throw new Error('Invalid edit count');
  const ordered = edits.map(edit => ({ ...edit })).sort((a, b) => a.start - b.start);
  let last = 0;
  let previousStart = -1;
  let after = '';
  for (const edit of ordered) {
    if (!Number.isSafeInteger(edit.start) || !Number.isSafeInteger(edit.end) ||
        edit.start < last || edit.start === previousStart || edit.end < edit.start || edit.end > before.length ||
        before.slice(edit.start, edit.end) !== edit.expected) throw new Error('Invalid or conflicting edit');
    // Refuse half of a UTF-16 surrogate pair; Ace offsets must preserve characters.
    for (const pos of [edit.start, edit.end]) {
      if (pos > 0 && pos < before.length && /[\uD800-\uDBFF]/.test(before[pos - 1]) &&
          /[\uDC00-\uDFFF]/.test(before[pos])) throw new Error('Edit splits a Unicode character');
    }
    after += before.slice(last, edit.start) + edit.replacement;
    last = edit.end;
    previousStart = edit.start;
  }
  const preview = Object.freeze({ before, after: after + before.slice(last),
    edits: Object.freeze(ordered.map(edit => Object.freeze(edit))) });
  previews.add(preview);
  return preview;
}

/**
 * Recheck immediately before changing the editor, without an intervening await.
 * The caller must still use the existing editor's undoable edit transaction.
 */
export function approvedText(preview: TextPreview, current: string, dirty: boolean, approved: boolean): string {
  if (!previews.has(preview)) throw new Error('Unknown change preview');
  if (!approved) throw new Error('Change not approved');
  if (dirty) throw new Error('Editor has unsaved changes');
  if (current !== preview.before) throw new Error('Document changed since preview');
  return preview.after;
}
