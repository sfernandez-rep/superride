// Live desktop test of Chat IA's reviewed edits (phase 3), against the
// SIMULATED Gemini API (tests/superrstudio/fixtures/fake-gemini.cjs).
// SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario chat-edit on the
// fixture project. Real: the IDE, the editor, the main process's proposal
// checks and the review cards. Simulated: the model's proposals. Checks that a
// proposal changes nothing until accepted; reject; accept through the editor
// (unsaved, undoable) and Revert; a proposal based on unsaved editor text; a
// stale proposal (editor changed afterwards); a change made on disk; two files
// accepted all-or-nothing; a path outside the project refused; current-file
// mode. The files on disk are never written by SuperR.
//
// "chat-real-edit" (profile gui-chat-real, the owner's key) asks Gemini to fix
// R/03-errores.R, accepts the proposal and checks in R that the result parses.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const mode = process.argv[2] || 'chat-edit';
const project = path.resolve(__dirname, '../..');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const rproj = process.env.SUPER_RSTUDIO_TEST_RPROJ;
const root = rproj ? path.dirname(rproj) : '';
const KEY = 'AIzaFakeSuperRGuiTestKey000000000000';
const log = (...args) => console.log(...args);
const disk = file => fs.readFileSync(path.join(root, ...file.split('/')), 'utf8');
const waitState = (page, pattern, timeout = 30000) => page.waitForFunction(
   source => new RegExp(source, 'i').test(document.querySelector('#superr_chat_ai_state')?.textContent || ''),
   pattern.source, {timeout});
const waitStatus = (page, pattern, timeout = 30000) => page.waitForFunction(
   source => new RegExp(source, 'i').test(document.querySelector('#superr_chat_ai_status')?.textContent || ''),
   pattern.source, {timeout});
const cards = page => page.locator('.superr-edit-card');
const lastCard = page => cards(page).last();
const editorText = page => page.evaluate(() => window.rstudio.documents.activeEditor().getValue());
const activePath = page => page.evaluate(() => window.rstudio.documents.active()?.path || '');

async function ask(page, message, timeout = 120000)
{
   const before = await page.locator('[id^="superr_chat_ai_answer_"]').count();
   await page.locator('#superr_chat_ai_prompt').fill(message);
   await page.locator('#superr_chat_ai_prompt').press('Enter');
   await page.waitForFunction(n => document.querySelectorAll('[id^="superr_chat_ai_answer_"]').length > n, before, {timeout: 30000});
   await page.waitForFunction(() => !/Generando|Generating/i.test(document.querySelector('#superr_chat_ai_state')?.textContent || ''),
      null, {timeout});
}

// closing is asynchronous: wait until no document is open, so a later open cannot see the old one
async function closeAll(page)
{
   await page.evaluate(() => window.rstudio.documents.closeAllNoSave());
   await page.waitForFunction(() => !window.rstudio.documents.active(), null, {timeout: 30000});
}

async function openScript(page, file)
{
   await page.evaluate(f => window.rstudio.documents.open(f), path.join(root, ...file.split('/')));
   await page.waitForFunction(name => (window.rstudio.documents.active()?.path || '').endsWith(name), path.basename(file), {timeout: 30000});
}

async function simulated(page)
{
   const original02 = disk('R/02-graficos.R'), original01 = disk('R/01-cargar.R');
   await page.locator('#superr_chat_ai_key').fill(KEY);
   await page.locator('#superr_chat_ai_save_key').click();
   await waitState(page, /Gemini conectado|Gemini connected/);
   await page.locator('#superr_chat_ai_context').selectOption('project');

   // a proposal changes nothing until it is accepted; reject
   await ask(page, 'Corregí el histograma');
   let card = lastCard(page);
   assert.match(await card.locator('.superr-edit-title').innerText(), /R\/02-graficos\.R\s+\(\+1 −1\)/);
   assert.match(await card.locator('.superr-diff-del').innerText(), /binwidth = 2/);
   assert.match(await card.locator('.superr-diff-add').innerText(), /binwidth = 1/);
   assert.equal(await card.getAttribute('data-state'), 'pending');
   assert.equal(disk('R/02-graficos.R'), original02);
   await card.locator('.superr-edit-reject').click();
   assert.equal(await card.getAttribute('data-state'), 'rejected');
   assert.equal(await card.locator('.superr-edit-accept').isVisible(), false);
   assert.equal(disk('R/02-graficos.R'), original02);
   log('PASS proposal shown with its diff; nothing changed; reject');

   // accept: opened in the editor, applied unsaved and undoable; Revert
   await ask(page, 'Corregí el histograma');
   card = lastCard(page);
   await card.locator('.superr-edit-accept').click();
   await page.waitForFunction(() => document.querySelectorAll('.superr-edit-card[data-state=applied]').length === 1, null, {timeout: 30000});
   assert.match(await activePath(page), /02-graficos\.R$/);
   assert.match(await editorText(page), /binwidth = 1/);
   assert.equal(disk('R/02-graficos.R'), original02, 'accepting wrote the file');
   await page.evaluate(() => window.rstudio.documents.activeEditor().undo());
   assert.match(await editorText(page), /binwidth = 2/, 'undo did not restore the text');
   await page.evaluate(() => window.rstudio.documents.activeEditor().redo());
   assert.match(await editorText(page), /binwidth = 1/);
   await card.locator('.superr-edit-revert').click();
   assert.match(await editorText(page), /binwidth = 2/);
   assert.equal(await card.getAttribute('data-state'), 'reverted');
   await page.screenshot({path: path.join(evidence, 'chat-edit-applied.png')});
   log('PASS accept applies in the editor (unsaved, undo/redo); Revert restores');

   // a proposal computed from unsaved editor text keeps that text
   await page.evaluate(() => {
      const editor = window.rstudio.documents.activeEditor();
      editor.setValue('# nota sin guardar\n' + editor.getValue(), 1);
   });
   await ask(page, 'Corregí el histograma');
   await lastCard(page).locator('.superr-edit-accept').click();
   await page.waitForFunction(() => [...document.querySelectorAll('.superr-edit-card')].pop().dataset.state === 'applied', null, {timeout: 30000});
   const applied = await editorText(page);
   assert.match(applied, /^# nota sin guardar\n/);
   assert.match(applied, /binwidth = 1/);
   log('PASS proposal based on unsaved editor text applied on top of it');

   // stale: the editor changes after the proposal (start again from the file on disk)
   await closeAll(page);
   await openScript(page, 'R/02-graficos.R');
   const cardsBefore = await cards(page).count();
   await ask(page, 'Cambiá el ancho');
   assert.equal(await cards(page).count(), cardsBefore + 1, 'no new proposal');
   const staleText = await editorText(page);
   await page.evaluate(() => window.rstudio.documents.activeEditor().setValue('# otra edición\n', 1));
   await lastCard(page).locator('.superr-edit-accept').click();
   await page.waitForFunction(() => [...document.querySelectorAll('.superr-edit-card')].pop().dataset.state === 'stale', null, {timeout: 30000});
   await waitStatus(page, /cambió después|changed after/);
   assert.equal(await editorText(page), '# otra edición\n');
   assert.notEqual(staleText, '# otra edición\n');
   await closeAll(page);
   log('PASS stale proposal refused; the editor keeps the newer text');

   // a change on disk after the proposal (file not open) is detected too
   await ask(page, 'Corregí el histograma');
   fs.writeFileSync(path.join(root, 'R', '02-graficos.R'), original02.replace('steelblue', 'gray'));
   await lastCard(page).locator('.superr-edit-accept').click();
   await page.waitForFunction(() => [...document.querySelectorAll('.superr-edit-card')].pop().dataset.state === 'stale', null, {timeout: 30000});
   fs.writeFileSync(path.join(root, 'R', '02-graficos.R'), original02);
   await closeAll(page);
   log('PASS a change made on disk after the proposal makes it stale');

   // two files, all or nothing
   await ask(page, 'Corregí ambos scripts');
   let accept = page.locator('.superr-edit-accept-all').last();
   assert.match(await accept.innerText(), /\(2\)/);
   await openScript(page, 'R/01-cargar.R');
   await page.evaluate(() => {
      const editor = window.rstudio.documents.activeEditor();
      editor.setValue(editor.getValue() + '# cambio concurrente\n', 1);
   });
   await accept.click();
   await waitStatus(page, /no se aplicó ningún cambio|no change was applied/).catch(async error => {
      log('diagnostics:', JSON.stringify(await page.evaluate(() => ({
         status: document.querySelector('#superr_chat_ai_status')?.textContent,
         cards: [...document.querySelectorAll('.superr-edit-card')].map(c => c.dataset.state + ' ' + c.querySelector('.superr-edit-title').textContent),
         active: window.rstudio.documents.active()?.path }))));
      throw error;
   });
   assert.deepEqual(await page.evaluate(() => [...document.querySelectorAll('.superr-edit-card')].slice(-2).map(c => c.dataset.state)).then(s => s.includes('applied')), false);
   await closeAll(page);
   await ask(page, 'Corregí ambos scripts');
   accept = page.locator('.superr-edit-accept-all').last();
   await accept.click();
   await page.waitForFunction(() => [...document.querySelectorAll('.superr-edit-card')].slice(-2).every(c => c.dataset.state === 'applied'),
      null, {timeout: 60000});
   await openScript(page, 'R/02-graficos.R');
   assert.match(await editorText(page), /binwidth = 1/);
   await openScript(page, 'R/01-cargar.R');
   assert.match(await editorText(page), /bin_size = 1/);
   assert.equal(disk('R/01-cargar.R'), original01);
   await closeAll(page);
   log('PASS two files: a concurrent change aborts both; otherwise both applied');

   // outside the project: refused by SuperR, no card
   const before = await cards(page).count();
   await ask(page, 'Corregí el archivo de fuera');
   assert.equal(await cards(page).count(), before);
   const outside = await page.locator('[id^="superr_chat_ai_answer_"]').last().innerText();
   assert.match(outside, /rechazado por SuperR: Not changeable/);
   log('PASS a path outside the project is refused:', outside.split('\n').pop());

   // current-file mode: only the attached document
   await openScript(page, 'R/02-graficos.R');
   await page.locator('#superr_chat_ai_context').selectOption('file');
   await ask(page, 'Corregí el color');
   await lastCard(page).locator('.superr-edit-accept').click();
   await page.waitForFunction(() => [...document.querySelectorAll('.superr-edit-card')].pop().dataset.state === 'applied', null, {timeout: 30000});
   assert.match(await editorText(page), /darkorange/);
   assert.equal(disk('R/02-graficos.R'), original02);
   assert.equal(disk('R/01-cargar.R'), original01);
   log('PASS current-file proposal applied to the open document; no file on disk was written');

   // saving is the user's step: the accepted text reaches the disk through the editor's own save
   const saveUntil = async (file, marker) => {
      await page.evaluate(() => window.rstudio.commands.saveSourceDoc());
      for (let i = 0; i < 40 && !disk(file).includes(marker); i++) await new Promise(r => setTimeout(r, 500));
      return disk(file);
   };
   const lf = text => text.replace(/\r\n/g, '\n');
   const eol = text => text.includes('\r\n') ? 'CRLF' : 'LF';
   const saved = await saveUntil('R/02-graficos.R', 'darkorange');
   assert.equal(lf(saved), lf(original02).replace('fill = "steelblue"', 'fill = "darkorange"'), 'the saved file differs from the accepted text');
   // control: a manual edit of another LF file, saved the same way, gets the same line endings
   // (RStudio's "Line ending format" preference, "native" by default, decides; Chat IA does not)
   await openScript(page, 'R/01-cargar.R');
   await page.evaluate(() => {
      const editor = window.rstudio.documents.activeEditor();
      editor.setValue(editor.getValue().replace('bin_size = 2', 'bin_size = 3'), 1);
   });
   const manual = await saveUntil('R/01-cargar.R', 'bin_size = 3');
   assert.equal(eol(saved), eol(manual), 'an accepted change was saved with other line endings than a manual edit');
   fs.writeFileSync(path.join(root, 'R', '02-graficos.R'), original02);
   fs.writeFileSync(path.join(root, 'R', '01-cargar.R'), original01);
   await closeAll(page);
   log(`PASS saving after accepting writes the accepted text; line endings as for a manual edit (${eol(saved)}, from ${eol(original02)})`);
}

async function real(page)
{
   await waitState(page, /Gemini conectado|Gemini connected/, 60000);
   const original = disk('R/03-errores.R');
   await openScript(page, 'R/03-errores.R');
   await page.locator('#superr_chat_ai_context').selectOption('project');
   await page.locator('#superr_chat_ai_prompt').fill('Corregí los errores de R/03-errores.R y mejorá la gráfica de ggplot2. ' +
      'Proponé el cambio con propose_file_edit.');
   await page.locator('#superr_chat_ai_prompt').press('Enter');
   await page.waitForFunction(() => document.querySelectorAll('[id^="superr_chat_ai_answer_"]').length > 0, null, {timeout: 30000});
   await page.waitForFunction(() => !/Generando|Generating/i.test(document.querySelector('#superr_chat_ai_state')?.textContent || ''),
      null, {timeout: 240000});
   const answer = await page.locator('[id^="superr_chat_ai_answer_"]').last().innerText();
   const activity = await page.evaluate(() => [...[...document.querySelectorAll('.superr-chat-user')].pop()
      .querySelectorAll('.superr-chat-activity')].map(n => n.textContent));
   log(`state: ${await page.locator('#superr_chat_ai_state').innerText()}; activity: ${activity.join(' | ')}`);
   log(`answer:\n${answer}`);
   const card = lastCard(page);
   assert.ok(await cards(page).count() > 0, 'Gemini made no proposal');
   log(`proposal: ${await card.locator('.superr-edit-title').innerText()}`);
   log(await card.locator('.superr-edit-diff').innerText());
   assert.equal(disk('R/03-errores.R'), original);
   await card.locator('.superr-edit-accept').click();
   await page.waitForFunction(() => [...document.querySelectorAll('.superr-edit-card')].pop().dataset.state === 'applied', null, {timeout: 30000});
   const fixed = await editorText(page);
   await page.screenshot({path: path.join(evidence, 'chat-edit-real.png')});
   assert.equal(disk('R/03-errores.R'), original, 'accepting wrote the file');
   // the corrected script must parse in R (checked in the console, not run)
   const before = await page.evaluate(() => window.rstudio.console.promptCount);
   await page.evaluate(code => {
      window.rstudio.commands.activateConsole();
      const editor = document.getElementById('rstudio_console_input').env.editor;
      editor.setValue(`tryCatch({ invisible(parse(text = ${JSON.stringify(code)})); cat("SUPERR_PARSE_OK\\n") }, ` +
         `error = function(e) cat("SUPERR_PARSE_FAIL", conditionMessage(e), "\\n"))`, 1);
      editor.focus();
   }, fixed);
   await page.keyboard.press('Enter');
   await page.waitForFunction(n => window.rstudio.console.promptCount > n, before, {timeout: 60000});
   const consoleText = await page.locator('#rstudio_workbench_panel_console').innerText();
   log(/SUPERR_PARSE_OK/.test(consoleText) ? 'R parse: OK' : `R parse: ${consoleText.split('\n').filter(l => /SUPERR_PARSE/.test(l)).pop()}`);
   assert.match(consoleText, /SUPERR_PARSE_OK/);
   assert.doesNotMatch(fixed, /binwdth/);
   log('PASS real Gemini edit proposal accepted in the editor; the result parses; the file on disk is unchanged');
}

(async () => {
   const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
   let page;
   for (let i = 0; i < 90 && !page; i++)
   {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(r => setTimeout(r, 1000));
   }
   assert.ok(page, 'no desktop page');
   await page.waitForFunction(() => window.rstudio?.ready, null, {timeout: 120000});
   await page.locator('#superr_chat_ai_toggle').click();
   try { if (mode === 'chat-real-edit') await real(page); else await simulated(page); }
   finally { await page.evaluate(() => window.rstudio.documents.closeAllNoSave()).catch(() => {}); }
   await browser.close();
})().catch(e => { console.error(e); process.exit(1); }); // exit: an open CDP connection would keep node alive
