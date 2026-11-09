const test = require('node:test');
const assert = require('node:assert/strict');
const { previewTextEdit, approvedText } = require('../../src/node/desktop/src/main/superr-agent/text-proposal');

test('preview preserves unchanged CRLF and Unicode; approval and conflicts are mandatory', () => {
  const before = '\ufeff# análisis 🐟\r\nx <- 1\r\ny <- 2\r\n';
  const start = before.indexOf('1');
  const preview = previewTextEdit(before, [{ start, end: start + 1, expected: '1', replacement: '3' }]);
  assert.equal(preview.after, before.replace('1', '3'));
  assert.throws(() => approvedText(preview, before, false, false), /not approved/);
  assert.throws(() => approvedText(preview, before, true, true), /unsaved/);
  assert.throws(() => approvedText(preview, before + '# changed', false, true), /changed/);
  assert.throws(() => approvedText({ ...preview, after: 'forged' }, before, false, true), /Unknown/);
  assert.equal(approvedText(preview, before, false, true), preview.after);
  assert.equal(before, preview.before); // original remains available for undo
});

test('refuses overlapping, stale, out-of-bounds and half-surrogate edits', () => {
  const before = 'a🐟bc';
  assert.throws(() => previewTextEdit(before, [{start: 2,end: 3,expected: before[2],replacement: ''}]), /Unicode/);
  assert.throws(() => previewTextEdit(before, [{start: 0,end: 1,expected: 'z',replacement: ''}]), /conflicting/);
  assert.throws(() => previewTextEdit(before, [{start: 0,end: 4,expected: 'a🐟b',replacement: ''},{start: 1,end: 3,expected: '🐟',replacement: ''}]), /conflicting/);
  assert.throws(() => previewTextEdit(before, [{start: -1,end: 2,expected: '',replacement: ''}]), /conflicting/);
});
