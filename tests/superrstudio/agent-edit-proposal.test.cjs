// Edit proposals (phase 3): exact-text edits, diff hunks, nothing written.
const test = require('node:test');
const assert = require('node:assert/strict');
const { applyEdits, diffLines, makeProposal, hashText, ProposalError } = require('../../src/node/desktop/src/main/superr-agent/edit-proposal');

const script = [
  '# 02-graficos.R',
  'library(ggplot2)',
  'p <- ggplot(tallas, aes(x = talla_cm)) +',
  '  geom_histogram(binwidth = 2, fill = "steelblue") +',
  '  labs(x = "Talla (cm)", y = "Frecuencia")',
  'print(p)',
  '',
].join('\n');

test('exact-text edits must match once, must not overlap, and keep CRLF documents CRLF', () => {
  const after = applyEdits(script, [
    { old_text: 'binwidth = 2', new_text: 'binwidth = 1' },
    { old_text: 'print(p)', new_text: 'print(p)\nggsave("tallas.png", p)' },
  ]);
  assert.match(after, /binwidth = 1/);
  assert.match(after, /ggsave\("tallas.png", p\)\n$/);
  assert.throws(() => applyEdits(script, [{ old_text: 'talla', new_text: 'x' }]), /occurs 2 times/);
  assert.throws(() => applyEdits(script, [{ old_text: 'no existe', new_text: 'x' }]), /occurs 0 times/);
  assert.throws(() => applyEdits(script, [{ old_text: 'library(ggplot2)\np', new_text: 'a' },
    { old_text: 'p <- ggplot', new_text: 'b' }]), ProposalError);
  assert.throws(() => applyEdits(script, []), /1 to 50/);
  assert.throws(() => applyEdits(script, [{ old_text: '', new_text: 'x' }]), /required/);
  const crlf = script.replace(/\n/g, '\r\n');
  const fixed = applyEdits(crlf, [{ old_text: 'print(p)\n', new_text: 'print(p)\nggsave("a.png")\n' }]);
  assert.equal(fixed.includes('\r\nggsave("a.png")\r\n'), true);
  assert.equal(/[^\r]\n/.test(fixed), false, 'a bare LF was introduced into a CRLF file');
  assert.equal(applyEdits('x <- "ñandú 🐟"\n', [{ old_text: '🐟', new_text: '🐠' }]), 'x <- "ñandú 🐠"\n');
});

test('diff hunks show context, additions and removals with line numbers', () => {
  const after = script.replace('binwidth = 2', 'binwidth = 1').replace('print(p)', 'print(p)\nggsave("t.png", p)');
  const { hunks, added, removed } = diffLines(script, after);
  assert.equal(added, 2);
  assert.equal(removed, 1);
  assert.equal(hunks.length, 1, 'nearby changes were not merged');
  const [h] = hunks;
  assert.equal(h.oldStart, 1);
  assert.deepEqual(h.lines.filter(l => l.type !== ' ').map(l => l.type + l.text), [
    '-  geom_histogram(binwidth = 2, fill = "steelblue") +', '+  geom_histogram(binwidth = 1, fill = "steelblue") +',
    '+ggsave("t.png", p)']);
  const far = Array.from({ length: 40 }, (_, i) => `x${i} <- ${i}`).join('\n') + '\n';
  const twoChanges = far.replace('x1 <- 1', 'x1 <- 100').replace('x38 <- 38', 'x38 <- 380');
  const split = diffLines(far, twoChanges);
  assert.equal(split.hunks.length, 2);
  assert.deepEqual(split.hunks.map(x => [x.oldStart, x.oldLines]), [[1, 5], [36, 5]]);
  assert.equal(diffLines(far, far.replace(/\n/g, '\r\n')).hunks.length, 0, 'line endings alone counted as changes');
});

test('a proposal records its base and refuses no-op or oversized changes', () => {
  const proposed = script.replace('steelblue', 'darkorange');
  const p = makeProposal({ path: 'R/02-graficos.R', idePath: '~/pesquerias/R/02-graficos.R', summary: 'color',
    original: script, proposed, source: 'disk' });
  assert.match(p.id, /^[0-9a-f]{16}$/);
  assert.equal(p.baseHash, hashText(script));
  assert.deepEqual([p.added, p.removed], [1, 1]);
  assert.throws(() => makeProposal({ path: 'a.R', idePath: '', summary: '', original: script, proposed: script, source: 'disk' }),
    /does not change/);
  assert.throws(() => makeProposal({ path: 'a.R', idePath: '', summary: '', original: 'x', proposed: 'y'.repeat(600000), source: 'disk' }),
    /too large/);
});
