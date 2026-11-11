const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { prepareAntigravityPolicy } = require('../../src/node/desktop/src/main/superr-agent/antigravity-policy');

test('private agent settings require approval and never overwrite modified settings', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-policy-'));
  try {
    const dir = await prepareAntigravityPolicy(root);
    const file = path.join(dir, 'antigravity-cli', 'settings.json');
    const data = JSON.parse(await fs.readFile(file, 'utf8'));
    assert.ok(data.permissions.ask.includes('write_file(*)'));
    assert.ok(data.permissions.ask.includes('command(*)'));
    assert.equal(await prepareAntigravityPolicy(root), dir);
    await fs.writeFile(file, '{"user":"keep"}');
    await assert.rejects(prepareAntigravityPolicy(root), /settings were changed/);
    assert.equal(await fs.readFile(file, 'utf8'), '{"user":"keep"}');
  } finally { await fs.rm(root, {recursive:true,force:true}); }
});
