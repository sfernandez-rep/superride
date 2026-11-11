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
    const otherReader = await ProjectReader.open(project);
    await assert.rejects(workspace.include(otherReader, 'secret.R'), /another project/);
    assert.equal(await fs.readFile(path.join(workspace.directory, 'scripts', 'uno.R'), 'utf8'), original);
    await assert.rejects(fs.access(path.join(workspace.directory, 'secret.R')));
    await assert.rejects(workspace.include(reader, '../secret.R'));
    workspace.seal();
    await assert.rejects(workspace.changes(otherReader), /another project/);
    await assert.rejects(workspace.include(reader, 'secret.R'), /sealed/);
    await fs.writeFile(path.join(workspace.directory, 'scripts', 'uno.R'), 'changed copy');
    assert.equal(await fs.readFile(path.join(project, 'scripts', 'uno.R'), 'utf8'), original);
    assert.equal(workspace.original('scripts/uno.R').text, original);
    const [change] = await workspace.changes(reader);
    assert.equal(change.file, 'scripts/uno.R');
    assert.equal(change.preview.before, original);
    assert.equal(change.preview.after, 'changed copy');
    assert.equal(change.conflict, false);
    await fs.writeFile(path.join(project, 'scripts', 'uno.R'), original + '# edited elsewhere\r\n');
    assert.equal((await workspace.changes(reader))[0].conflict, true);
    await fs.writeFile(path.join(project, 'scripts', 'uno.R'), original);
    await workspace.cleanup();
    await assert.rejects(fs.access(workspace.directory));
    assert.equal(await fs.readFile(path.join(project, 'scripts', 'uno.R'), 'utf8'), original);
  } finally { if (workspace) await workspace.cleanup(); await fs.rm(root, {recursive:true,force:true}); }
});

test('review fails closed when a staged file is replaced with a link', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-stage-'));
  const project = path.join(root, 'project');
  await fs.mkdir(project);
  await fs.writeFile(path.join(project, 'main.R'), 'x <- 1\n');
  const reader = await ProjectReader.open(project);
  const workspace = await StagedWorkspace.create(path.join(root, 'private'));
  try {
    await workspace.include(reader, 'main.R');
    workspace.seal();
    const staged = path.join(workspace.directory, 'main.R');
    await fs.unlink(staged);
    try {
      await fs.symlink(path.join(project, 'main.R'), staged, 'file');
    } catch (error) {
      if (error.code === 'EPERM' || error.code === 'EACCES') return;
      throw error;
    }
    await assert.rejects(workspace.changes(reader), /links are not allowed/);
    assert.equal(await fs.readFile(path.join(project, 'main.R'), 'utf8'), 'x <- 1\n');
  } finally { await workspace.cleanup(); await fs.rm(root, {recursive:true,force:true}); }
});
