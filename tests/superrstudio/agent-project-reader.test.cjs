const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { ProjectReader } = require('../../src/node/desktop/src/main/superr-agent/project-reader');

test('reads selected UTF-8 files and rejects traversal, secrets, binaries and junctions', async () => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-agent-'));
  const root = path.join(temp, 'project');
  await fs.mkdir(root);
  try {
    await fs.writeFile(path.join(root, 'análisis.R'), 'x <- "á"\r\n');
    await fs.writeFile(path.join(root, '.Renviron'), 'SECRET=private');
    await fs.writeFile(path.join(root, 'data.csv'), Buffer.from([65, 0, 66]));
    await fs.writeFile(path.join(root, 'large.txt'), Buffer.alloc(1024 * 1024 + 1, 65));
    await fs.writeFile(path.join(temp, 'outside.R'), 'private');
    await fs.symlink(temp, path.join(root, 'outside'), process.platform === 'win32' ? 'junction' : 'dir');
    const reader = await ProjectReader.open(root);
    assert.equal(await reader.read('análisis.R'), 'x <- "á"\r\n');
    for (const name of ['../outside.R', '.Renviron', '.env.txt', 'outside/outside.R', 'data.csv', 'large.txt', path.join(temp, 'outside.R')])
      await assert.rejects(reader.read(name));
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});
