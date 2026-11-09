const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { ConversationStore } = require('../../src/node/desktop/src/main/superr-agent/conversation-store');

test('history persists by project and provider, validates input and supports deletion', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-history-test-'));
  try {
    const store = await ConversationStore.open(root);
    const project = path.join(root, 'project');
    const first = await store.create(project, 'codex');
    const second = await store.create(project, 'antigravity');
    await store.create(null, 'codex');
    first.sessionId = 'session-1';
    first.messages.push({ role: 'user', text: '¿Cómo funciona?', files: ['análisis.R'], time: new Date().toISOString() });
    await store.save(first);
    const reopened = await ConversationStore.open(root);
    assert.deepEqual(await reopened.read(first.id), first);
    assert.deepEqual(new Set((await reopened.list(project)).map(item => item.id)), new Set([first.id, second.id]));
    assert.equal((await reopened.list(null)).length, 1);
    await assert.rejects(reopened.read('../credentials'), /Invalid conversation ID/);
    await assert.rejects(reopened.save({ ...first, provider: 'invalid' }), /Invalid conversation/);
    await reopened.delete(first.id);
    assert.equal(await reopened.read(first.id), null);
    assert.equal((await reopened.list(project)).length, 1);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});

test('history rejects symlink files and malformed data', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-history-test-'));
  try {
    const store = await ConversationStore.open(root);
    const item = await store.create(null, 'codex');
    const file = path.join(root, `${item.id}.json`);
    await fs.writeFile(file, '{broken');
    await assert.rejects(store.read(item.id), /Cannot read conversation/);
    await fs.unlink(file);
    const target = path.join(root, 'other');
    await fs.writeFile(target, 'private');
    try {
      await fs.symlink(target, file, 'file');
      await assert.rejects(store.read(item.id), /Cannot read conversation/);
    } catch (error) {
      if (!['EPERM', 'EACCES'].includes(error.code)) throw error;
    }
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});
