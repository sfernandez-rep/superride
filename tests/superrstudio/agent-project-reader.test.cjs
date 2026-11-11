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
    await fs.writeFile(path.join(root, 'bom.Rmd'), '\ufeff# título\r\n');
    await fs.writeFile(path.join(root, '.Renviron'), 'SECRET=private');
    await fs.writeFile(path.join(root, 'data.csv'), Buffer.from([65, 0, 66]));
    await fs.writeFile(path.join(root, 'large.txt'), Buffer.alloc(1024 * 1024 + 1, 65));
    await fs.writeFile(path.join(root, 'datos.Rds'), Buffer.from([1, 2, 3]));
    await fs.mkdir(path.join(root, 'scripts'));
    await fs.writeFile(path.join(root, 'scripts', 'otro.R'), '# análisis relacionado\r\nx <- 3\r\n');
    await fs.writeFile(path.join(temp, 'outside.R'), 'private');
    await fs.symlink(temp, path.join(root, 'outside'), process.platform === 'win32' ? 'junction' : 'dir');
    const reader = await ProjectReader.open(root);
    assert.equal(await reader.read('análisis.R'), 'x <- "á"\r\n');
    assert.equal(await reader.read('bom.Rmd'), '\ufeff# título\r\n');
    const listing = await reader.list();
    assert.ok(listing.files.includes('datos.Rds'));
    assert.ok(listing.files.includes('scripts/otro.R'));
    assert.ok(!listing.files.some(name => name.includes('outside') || name.includes('Renviron')));
    assert.deepEqual((await reader.search('RELACIONADO')).matches.map(x => [x.file, x.line]), [['scripts/otro.R', 1]]);
    await assert.rejects(reader.read('datos.Rds'));
    for (const name of ['../outside.R', '.Renviron', '.env.txt', 'outside/outside.R', 'data.csv', 'large.txt', path.join(temp, 'outside.R')])
      await assert.rejects(reader.read(name));
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});
