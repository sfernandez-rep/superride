// Read-only project context for Chat IA and the bridge's function loop.
// Real temporary projects on disk; Gemini responses are simulated (fake fetch).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { ProjectContext, parseContext, ContextError } = require('../../src/node/desktop/src/main/superr-agent/project-context');
const { GeminiApi } = require('../../src/node/desktop/src/main/superr-agent/gemini-api');
const { ChatBridge } = require('../../src/node/desktop/src/main/superr-agent/chat-bridge');

async function project() {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-context-'));
  const root = path.join(temp, 'pesquerias');
  await fs.mkdir(path.join(root, 'R'), { recursive: true });
  await fs.mkdir(path.join(root, 'datos'));
  await fs.writeFile(path.join(root, 'pesquerias.Rproj'), 'Version: 1.0\n');
  await fs.writeFile(path.join(root, 'R', '01-cargar.R'), 'library(TropFishR)\nsource("R/02-graficos.R")\ntallas <- read.csv("datos/tallas.csv")\n');
  await fs.writeFile(path.join(root, 'R', '02-graficos.R'), 'p <- ggplot2::ggplot(tallas, ggplot2::aes(talla)) + ggplot2::geom_histogram()\n');
  await fs.writeFile(path.join(root, 'análisis.R'), '# análisis de tallas: ñandú\nmedia <- mean(tallas$talla)\n');
  await fs.writeFile(path.join(root, 'datos', 'tallas.csv'), 'talla,peso\n' + Array.from({ length: 6000 }, (_, i) => `${i},${i * 2}`).join('\n'));
  await fs.writeFile(path.join(root, 'datos', 'modelo.rds'), Buffer.from([0x58, 0x0a, 0, 0, 0, 3]));
  await fs.writeFile(path.join(root, '.env'), 'GEMINI_API_KEY=secreto');
  await fs.writeFile(path.join(root, 'secrets.R'), 'token <- "x"');
  await fs.writeFile(path.join(temp, 'fuera.R'), 'privado <- TRUE');
  await fs.symlink(temp, path.join(root, 'enlace'), process.platform === 'win32' ? 'junction' : 'dir');
  return { temp, root };
}
const doc = (root, rel, content, dirty, selection) => ({ path: path.join(root, ...rel.split('/')), name: path.basename(rel),
  content, dirty, ...(selection ? { selection } : {}) });

test('project roots must be real R projects, never the home folder or a drive root', async () => {
  const { temp, root } = await project();
  try {
    await assert.rejects(ProjectContext.open({ mode: 'project' }), e => e.code === 'no_project');
    await assert.rejects(ProjectContext.open({ mode: 'project', projectRoot: 'relative/dir' }), e => e.code === 'invalid_project');
    await assert.rejects(ProjectContext.open({ mode: 'project', projectRoot: temp }), e => e.code === 'invalid_project');
    await assert.rejects(ProjectContext.open({ mode: 'project', projectRoot: os.homedir() }), e => e.code === 'home_folder' || e.code === 'invalid_project');
    await assert.rejects(ProjectContext.open({ mode: 'project', projectRoot: path.parse(root).root }), e => e.code === 'invalid_project');
    await assert.rejects(ProjectContext.open({ mode: 'project', projectRoot: path.dirname(os.homedir()) }), e => e.code === 'home_folder' || e.code === 'invalid_project');
    await assert.rejects(ProjectContext.open({ mode: 'file' }), e => e.code === 'no_document');
    assert.throws(() => parseContext({ mode: 'everything' }), ContextError);
    assert.throws(() => parseContext({ mode: 'file', active: { name: 'x', content: 3, dirty: false } }), ContextError);
    assert.deepEqual(parseContext(undefined), { mode: 'general' });
    // a personal folder (for example RStudio's ~) is never a project, nor any folder containing it
    await assert.rejects(ProjectContext.open({ mode: 'project', projectRoot: root }, { homes: [root] }), e => e.code === 'home_folder');
    await assert.rejects(ProjectContext.open({ mode: 'project', projectRoot: root }, { homes: [path.join(root, 'R')] }),
      e => e.code === 'home_folder');
    await ProjectContext.open({ mode: 'project', projectRoot: root }, { homes: [temp + '-otro'] });
    const empty = path.join(temp, 'vacio');
    await fs.mkdir(empty);
    await fs.writeFile(path.join(empty, 'vacio.Rproj'), '');
    const scope = await ProjectContext.open({ mode: 'project', projectRoot: empty });
    assert.match(await scope.instruction(), /\(no readable files\)/);
    assert.deepEqual((await scope.call('list_project_files', {})).response.files, []);
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});

test('the index and reads stay inside the project and prefer unsaved editor changes', async () => {
  const { temp, root } = await project();
  try {
    const active = doc(root, 'R/02-graficos.R', 'p <- ggplot2::ggplot(tallas) # sin guardar\n', true, 'ggplot2::ggplot(tallas)');
    const scope = await ProjectContext.open({ mode: 'project', projectRoot: root, active, open: [active] });
    const instruction = await scope.instruction();
    assert.match(instruction, /R\/01-cargar\.R \(\d+ bytes\)/);
    assert.match(instruction, /R\/02-graficos\.R \(\d+ bytes, unsaved changes in the editor\)/);
    assert.match(instruction, /datos\/modelo\.rds \(6 bytes, binary R data\)/);
    assert.match(instruction, /análisis\.R/);
    assert.doesNotMatch(instruction, /\.env|secrets|enlace|fuera/);
    assert.equal(scope.files.length, 0, 'the index disclosed file contents');

    const read = await scope.call('read_project_files', { paths: ['R/01-cargar.R', 'R/02-graficos.R', 'análisis.R',
      'datos/tallas.csv', 'datos/modelo.rds', '../fuera.R', 'enlace/fuera.R', '.env', 'secrets.R', 'C:/Windows/win.ini'] });
    const more = await scope.call('read_project_files', { paths: ['secrets.R', 'C:/Windows/win.ini'] });
    const byPath = Object.fromEntries([...read.response.files, ...more.response.files].map(f => [f.path, f]));
    assert.match(byPath['R/01-cargar.R'].content, /library\(TropFishR\)/);
    assert.match(byPath['R/02-graficos.R'].content, /sin guardar/);
    assert.equal(byPath['R/02-graficos.R'].source, 'editor (unsaved changes)');
    assert.match(byPath['análisis.R'].content, /ñandú/);
    assert.equal(byPath['datos/tallas.csv'].truncated, true);
    assert.ok(byPath['datos/tallas.csv'].content.length <= 32 * 1024);
    assert.match(byPath['datos/modelo.rds'].note, /does not read it/);
    assert.equal(byPath['datos/modelo.rds'].content, undefined);
    for (const blocked of ['../fuera.R', 'enlace/fuera.R', '.env', 'secrets.R', 'C:/Windows/win.ini'])
      assert.ok(byPath[blocked].error, `${blocked} was read`);
    assert.equal(read.response.files.length, 8, 'more than 8 paths read in one call');
    assert.deepEqual(read.files.map(f => [f.path, f.source]).sort(), [
      ['R/01-cargar.R', 'disk'], ['R/02-graficos.R', 'editor-unsaved'], ['análisis.R', 'disk'], ['datos/tallas.csv', 'disk']].sort());

    const summary = (await scope.call('get_project_context', {})).response;
    assert.deepEqual(summary.packages, ['TropFishR', 'ggplot2']);
    assert.equal(summary.active_document, 'R/02-graficos.R');
    const search = await scope.call('search_project_files', { query: 'TALLAS' });
    assert.ok(search.response.matches.some(m => m.file === 'análisis.R'));
    assert.equal((await scope.call('get_selected_code', {})).response.selection, 'ggplot2::ggplot(tallas)');
    assert.match((await scope.call('get_active_document', {})).response.content, /sin guardar/);
    assert.match((await scope.call('run_r_code', {})).response.error, /Unknown function/);

    // the editor may name a document by another path to the same file (a link, a
    // junction, or a Windows 8.3 short name as on CI runners): unsaved text still wins
    const alias = path.join(temp, 'alias');
    await fs.symlink(root, alias, process.platform === 'win32' ? 'junction' : 'dir');
    const aliased = doc(alias, 'R/02-graficos.R', '# por otro camino\n', true);
    const viaAlias = await ProjectContext.open({ mode: 'project', projectRoot: root, active: aliased, open: [aliased] });
    assert.match(await viaAlias.instruction(), /R\/02-graficos\.R \(\d+ bytes, unsaved changes in the editor\)/);
    assert.match((await viaAlias.call('read_project_files', { paths: ['R/02-graficos.R'] })).response.files[0].content, /por otro camino/);
    assert.equal((await viaAlias.call('get_active_document', {})).response.path, 'R/02-graficos.R');

    const outside = await ProjectContext.open({ mode: 'project', projectRoot: root,
      active: { path: path.join(temp, 'fuera.R'), name: 'fuera.R', content: 'privado <- TRUE', dirty: false } });
    assert.match((await outside.call('get_active_document', {})).response.error, /inside the authorised project/);
    assert.equal(outside.files.length, 0);
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});

test('file mode attaches only the active document, with unsaved changes and selection', async () => {
  const scope = await ProjectContext.open({ mode: 'file', active: { name: 'Untitled1', content: 'x <- c(1, NA)\nmean(x)\n',
    dirty: true, selection: 'mean(x)' } });
  const attachment = scope.attachment();
  assert.match(attachment, /active editor document "Untitled1" \(with unsaved changes\)/);
  assert.match(attachment, /mean\(x\)/);
  assert.match(attachment, /Selected code/);
  assert.deepEqual(scope.files, [{ path: 'Untitled1', source: 'editor-unsaved', truncated: false }]);
  assert.deepEqual(scope.tools().map(t => t.name), ['propose_file_edit']);
  const general = await ProjectContext.open({ mode: 'general' });
  assert.equal(general.attachment(), '');
  assert.deepEqual(general.tools(), []);
});

const KEY = 'AIzaFakeKeyForUnitTests000000000000';
const sse = chunks => new Response(chunks.map(c => `data: ${JSON.stringify(c)}\r\n\r\n`).join(''), { status: 200 });

test('bridge: function calls are answered by SuperR, thought signatures go back, files are reported', async () => {
  const { temp, root } = await project();
  const bodies = [], events = [];
  try {
    const gemini = new GeminiApi(async (url, init) => {
      const body = JSON.parse(init.body);
      bodies.push(body);
      if (bodies.length === 1)
        return sse([{ candidates: [{ content: { role: 'model', parts: [
          { text: 'Voy a leer los scripts. ' },
          { functionCall: { name: 'read_project_files', args: { paths: ['R/01-cargar.R', 'R/02-graficos.R'] } }, thoughtSignature: 'SIG-1' }] },
          finishReason: 'STOP' }] }]);
      return sse([{ candidates: [{ content: { role: 'model', parts: [{ text: '01-cargar.R carga TropFishR.' }] }, finishReason: 'STOP' }] }]);
    });
    const secrets = { loadSecret: async () => KEY, saveSecret: async () => {}, remove: async () => {} };
    const bridge = new ChatBridge(async () => ({}), async () => {}, { secrets: async () => secrets, gemini, onEvent: e => events.push(e) });
    const result = await bridge.send('gemini-api', 'Analizá los scripts', 'gemini-3.6-flash', 'p1', { mode: 'project', projectRoot: root });
    assert.equal(result.status, 'completed');
    assert.deepEqual(result.files.map(f => f.path).sort(), ['R/01-cargar.R', 'R/02-graficos.R']);
    assert.equal(bodies.length, 2);
    assert.ok(bodies[0].tools[0].functionDeclarations.some(f => f.name === 'read_project_files'));
    assert.match(bodies[0].systemInstruction.parts[0].text, /File index/);
    const [user, model, reply] = bodies[1].contents;
    assert.equal(user.role, 'user');
    assert.deepEqual(model.parts[1], { functionCall: { name: 'read_project_files', args: { paths: ['R/01-cargar.R', 'R/02-graficos.R'] } },
      thoughtSignature: 'SIG-1' });
    assert.equal(reply.role, 'user');
    assert.match(reply.parts[0].functionResponse.response.files[0].content, /library\(TropFishR\)/);
    assert.deepEqual(events.filter(e => e.kind === 'tool').map(e => [e.tool, e.files.length]), [['read_project_files', 2]]);
    assert.equal(events.filter(e => e.text).map(e => e.text).join(''), 'Voy a leer los scripts. 01-cargar.R carga TropFishR.');

    // general mode: no tools, no index
    await bridge.newChat('gemini-api');
    await bridge.send('gemini-api', 'Hola', 'gemini-3.6-flash', 'p2');
    assert.equal(bodies[2].tools, undefined);
    assert.doesNotMatch(bodies[2].systemInstruction.parts[0].text, /File index/);

    // context errors are reported, not thrown
    assert.deepEqual(await bridge.send('gemini-api', 'x', 'gemini-3.6-flash', 'p3', { mode: 'project', projectRoot: temp }),
      { status: 'error', kind: 'context', detail: 'invalid_project' });
    assert.deepEqual(await bridge.send('gemini-api', 'x', 'gemini-3.6-flash', 'p4', { mode: 'nonsense' }),
      { status: 'error', kind: 'context', detail: 'invalid_context' });
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});

test('bridge: a quota error during a read keeps the list of disclosed files; rounds are limited', async () => {
  const { temp, root } = await project();
  try {
    let n = 0;
    const call = { candidates: [{ content: { role: 'model', parts: [{ functionCall: { name: 'read_project_files', args: { paths: ['análisis.R'] } } }] },
      finishReason: 'STOP' }] };
    const quota = new GeminiApi(async () => ++n === 1 ? sse([call]) : new Response(JSON.stringify({ error: { code: 429,
      status: 'RESOURCE_EXHAUSTED', message: 'quota', details: [{ '@type': 'type.googleapis.com/google.rpc.RetryInfo', retryDelay: '30s' }] } }), { status: 429 }));
    const secrets = { loadSecret: async () => KEY, saveSecret: async () => {}, remove: async () => {} };
    let bridge = new ChatBridge(async () => ({}), async () => {}, { secrets: async () => secrets, gemini: quota });
    const failed = await bridge.send('gemini-api', 'Leé análisis.R', 'gemini-3.6-flash', 'q1', { mode: 'project', projectRoot: root });
    assert.equal(failed.kind, 'quota');
    assert.equal(failed.quota.retryAfterSeconds, 30);
    assert.deepEqual(failed.files.map(f => f.path), ['análisis.R']);

    let requests = 0;
    const endless = new GeminiApi(async () => { requests++; return sse([call]); });
    bridge = new ChatBridge(async () => ({}), async () => {}, { secrets: async () => secrets, gemini: endless });
    const limited = await bridge.send('gemini-api', 'x', 'gemini-3.6-flash', 'q2', { mode: 'project', projectRoot: root });
    assert.deepEqual([limited.status, limited.finishReason], ['incomplete', 'TOOL_ROUNDS']);
    assert.equal(requests, 5);
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});

test('proposals: from the unsaved buffer or disk, scripts inside the project only, never written', async () => {
  const { temp, root } = await project();
  try {
    const dirty = doc(root, 'R/02-graficos.R', 'p <- ggplot2::ggplot(tallas) # sin guardar\n', true);
    const scope = await ProjectContext.open({ mode: 'project', projectRoot: root, open: [dirty] },
      { aliasPath: absolute => '~ALIAS/' + path.basename(absolute) });
    const fromBuffer = await scope.call('propose_file_edit', { path: 'R/02-graficos.R', summary: 'quita el comentario',
      edits: [{ old_text: ' # sin guardar', new_text: '' }] });
    assert.equal(fromBuffer.response.status, 'proposed');
    assert.equal(fromBuffer.proposal.source, 'editor-unsaved');
    assert.equal(fromBuffer.proposal.idePath, '~ALIAS/02-graficos.R');
    assert.equal(fromBuffer.proposal.proposed, 'p <- ggplot2::ggplot(tallas)\n');
    const fromDisk = await scope.call('propose_file_edit', { path: 'R/01-cargar.R', summary: 'x',
      edits: [{ old_text: 'library(TropFishR)', new_text: 'library(TropFishR)\nlibrary(dplyr)' }] });
    assert.equal(fromDisk.proposal.source, 'disk');
    assert.match(fromDisk.response.note, /NOT been applied/);
    assert.equal(await fs.readFile(path.join(root, 'R', '01-cargar.R'), 'utf8'),
      'library(TropFishR)\nsource("R/02-graficos.R")\ntallas <- read.csv("datos/tallas.csv")\n', 'a proposal wrote the file');
    for (const [target, reason] of [['../fuera.R', /Not changeable/], ['enlace/fuera.R', /Not changeable/],
      ['datos/tallas.csv', /Only \.R/], ['secrets.R', /Not changeable/]])
      assert.match((await scope.call('propose_file_edit', { path: target, summary: '', edits: [{ old_text: 'x', new_text: 'y' }] }))
        .response.error, reason, target);
    assert.match((await scope.call('propose_file_edit', { path: 'R/01-cargar.R', summary: '',
      edits: [{ old_text: 'no existe', new_text: 'y' }] })).response.error, /occurs 0 times/);

    const file = await ProjectContext.open({ mode: 'file', active: { name: 'Untitled1', content: 'x <- 1\n', dirty: true } });
    const own = await file.call('propose_file_edit', { path: 'Untitled1', summary: 'y', edits: [{ old_text: 'x <- 1', new_text: 'x <- 2' }] });
    assert.deepEqual([own.proposal.idePath, own.proposal.source], ['', 'editor-unsaved']);
    assert.match((await file.call('propose_file_edit', { path: 'otro.R', summary: '', edits: [{ old_text: 'x', new_text: 'y' }] }))
      .response.error, /only the attached document/);
    assert.match((await file.call('read_project_files', { paths: ['otro.R'] })).response.error, /not enabled/);
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});

test('bridge: a proposal is published to the panel and the model is told it is not applied', async () => {
  const { temp, root } = await project();
  const bodies = [], events = [];
  try {
    const gemini = new GeminiApi(async (url, init) => {
      bodies.push(JSON.parse(init.body));
      if (bodies.length === 1)
        return sse([{ candidates: [{ content: { role: 'model', parts: [{ functionCall: { name: 'propose_file_edit', args: {
          path: 'R/02-graficos.R', summary: 'histograma más fino', edits: [{ old_text: 'geom_histogram()', new_text: 'geom_histogram(bins = 30)' }] } },
          thoughtSignature: 'S' }] }, finishReason: 'STOP' }] }]);
      return sse([{ candidates: [{ content: { role: 'model', parts: [{ text: 'Te propuse un cambio.' }] }, finishReason: 'STOP' }] }]);
    });
    const secrets = { loadSecret: async () => KEY, saveSecret: async () => {}, remove: async () => {} };
    const bridge = new ChatBridge(async () => ({}), async () => {}, { secrets: async () => secrets, gemini, onEvent: e => events.push(e),
      aliasPath: absolute => absolute.replace(/\\/g, '/') });
    const result = await bridge.send('gemini-api', 'Mejorá el histograma', 'gemini-3.6-flash', 'e1', { mode: 'project', projectRoot: root });
    assert.equal(result.status, 'completed');
    const proposal = events.find(e => e.kind === 'proposal').proposal;
    assert.deepEqual(result.proposals.map(p => p.id), [proposal.id], 'the reply does not repeat the proposals of the turn');
    assert.equal(proposal.path, 'R/02-graficos.R');
    assert.match(proposal.idePath, /pesquerias\/R\/02-graficos\.R$/);
    assert.match(proposal.proposed, /geom_histogram\(bins = 30\)/);
    assert.equal(bodies[1].contents[2].parts[0].functionResponse.response.status, 'proposed');
    assert.ok(bodies[0].tools[0].functionDeclarations.some(f => f.name === 'propose_file_edit'));
    assert.match(await fs.readFile(path.join(root, 'R', '02-graficos.R'), 'utf8'), /geom_histogram\(\)/, 'the file was written');
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});
