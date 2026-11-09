const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { ProjectReader } = require('../../src/node/desktop/src/main/superr-agent/project-reader');
const { StagedWorkspace } = require('../../src/node/desktop/src/main/superr-agent/staged-workspace');

test('only explicitly selected files are staged; originals and BOM remain intact', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-stage-'));
  const project = path.join(root, 'project'), staging = path.join(root, 'private');
  await fs.mkdir(path.join(project, 'scripts'), {recursive:true});
  const original = '\ufeff# estudio 🐟\r\nx <- 1\r\n';
  await fs.writeFile(path.join(project, 'scripts', 'uno.R'), original);
  await fs.writeFile(path.join(project, 'secret.R'), 'not selected');
  let workspace;
  try {
    workspace = await StagedWorkspace.create(staging);
    const reader = await ProjectReader.open(project);
    await workspace.include(reader, 'scripts/uno.R');
    assert.equal(await fs.readFile(path.join(workspace.directory, 'scripts', 'uno.R'), 'utf8'), original);
    await assert.rejects(fs.access(path.join(workspace.directory, 'secret.R')));
    await assert.rejects(workspace.include(reader, '../secret.R'));
    workspace.seal();
    await assert.rejects(workspace.include(reader, 'secret.R'), /sealed/);
    await fs.writeFile(path.join(workspace.directory, 'scripts', 'uno.R'), 'changed copy');
    assert.equal(await fs.readFile(path.join(project, 'scripts', 'uno.R'), 'utf8'), original);
    assert.equal(workspace.original('scripts/uno.R').text, original);
    await workspace.cleanup();
    await assert.rejects(fs.access(workspace.directory));
    assert.equal(await fs.readFile(path.join(project, 'scripts', 'uno.R'), 'utf8'), original);
  } finally { if (workspace) await workspace.cleanup(); await fs.rm(root, {recursive:true,force:true}); }
});
