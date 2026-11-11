// Live desktop test of Chat IA's project context (phase 2), against the
// SIMULATED Gemini API (tests/superrstudio/fixtures/fake-gemini.cjs).
// SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario chat-project:
// the desktop opens the project made by fixtures/make-chat-project.cjs. Real:
// the IDE, the editor snapshot (unsaved changes, selection), the IPC, the main
// process's path checks and file reads. Simulated: the model, which asks to
// read the scripts SuperR lists and echoes what it received. Checks general,
// current-file and project modes, the activity lines, editor actions, a quota
// error during a read, and refused project roots.
//
// "chat-real-project" (profile gui-chat-real, the owner's own key) sends one
// real project question; it uses a few requests of the owner's free quota.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');

const mode = process.argv[2] || 'chat-project';
const project = path.resolve(__dirname, '../..');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const rproj = process.env.SUPER_RSTUDIO_TEST_RPROJ;
const KEY = 'AIzaFakeSuperRGuiTestKey000000000000';
const log = (...args) => console.log(...args);
const waitState = (page, pattern, timeout = 30000) => page.waitForFunction(
   source => new RegExp(source, 'i').test(document.querySelector('#superr_chat_ai_state')?.textContent || ''),
   pattern.source, {timeout});
const waitStatus = (page, pattern, timeout = 30000) => page.waitForFunction(
   source => new RegExp(source, 'i').test(document.querySelector('#superr_chat_ai_status')?.textContent || ''),
   pattern.source, {timeout});
const lastAnswer = page => page.locator('[id^="superr_chat_ai_answer_"]').last();
const lastActivity = page => page.evaluate(() => [...document.querySelectorAll('.superr-chat-user')].pop()
   ?.querySelectorAll('.superr-chat-activity').length ? [...[...document.querySelectorAll('.superr-chat-user')].pop()
   .querySelectorAll('.superr-chat-activity')].map(n => n.textContent) : []);

// a simulated answer can finish before "Generating" is ever observed: wait for the new answer instead
async function ask(page, message, done = /Gemini conectado|Gemini connected/)
{
   const before = await page.locator('[id^="superr_chat_ai_answer_"]').count();
   await page.locator('#superr_chat_ai_prompt').fill(message);
   await page.locator('#superr_chat_ai_prompt').press('Enter');
   await page.waitForFunction(n => document.querySelectorAll('[id^="superr_chat_ai_answer_"]').length > n, before, {timeout: 30000});
   await page.waitForFunction(() => !/Generando|Generating/i.test(document.querySelector('#superr_chat_ai_state')?.textContent || ''),
      null, {timeout: 120000});
   await waitState(page, done, 120000);
}

async function simulated(page)
{
   const root = path.dirname(rproj);
   await page.locator('#superr_chat_ai_key').fill(KEY);
   await page.locator('#superr_chat_ai_save_key').click();
   await waitState(page, /Gemini conectado|Gemini connected/);
   assert.match(await page.locator('#superr_chat_ai_context option[value=project]').innerText(), /pesquerias/);

   // general: nothing disclosed
   await page.locator('#superr_chat_ai_context').selectOption('general');
   await ask(page, 'hola');
   assert.deepEqual(await lastActivity(page), []);

   // current file with unsaved changes and a selection
   await page.evaluate(file => window.rstudio.documents.open(file), path.join(root, 'R', '02-graficos.R'));
   await page.waitForFunction(() => /02-graficos/.test(window.rstudio.documents.active()?.path || ''), null, {timeout: 30000});
   await page.evaluate(() => {
      const editor = window.rstudio.documents.activeEditor();
      editor.setValue('# cambio sin guardar en el editor\n' + editor.getValue(), 1);
   });
   await page.locator('#superr_chat_ai_context').selectOption('file');
   await waitStatus(page, /Privacidad|Privacy/);
   await ask(page, '¿Qué hace este archivo?');
   const fileActivity = await lastActivity(page);
   assert.match(fileActivity.join(' '), /02-graficos\.R \((sin guardar|unsaved)\)/);
   assert.match(await lastAnswer(page).innerText(), /sin guardar: sí\). Primera línea: # cambio sin guardar en el editor/);
   log('PASS current file: the unsaved editor text was sent and reported:', fileActivity.join(' | '));

   // project: the model asks for the scripts; SuperR reads them (unsaved buffer first)
   await page.locator('#superr_chat_ai_context').selectOption('project');
   await ask(page, 'Analizá los scripts de este proyecto y explicame qué hace cada uno');
   const projectActivity = (await lastActivity(page)).join(' | ');
   assert.match(projectActivity, /R\/01-cargar\.R/);
   assert.match(projectActivity, /R\/02-graficos\.R \((sin guardar|unsaved)\)/);
   assert.match(projectActivity, /análisis_ñandú\.R/);
   assert.doesNotMatch(projectActivity, /enlace|fuera|\.env/);
   const answer = await lastAnswer(page).innerText();
   assert.match(answer, /01-cargar\.R: # 01-cargar\.R: lee las tallas/);
   assert.match(answer, /02-graficos\.R: # cambio sin guardar en el editor/);
   assert.match(answer, /análisis_ñandú\.R: # análisis_ñandú\.R: resumen con acentos/);
   assert.doesNotMatch(answer, /no-debe-salir|secreto_fuera/);
   await page.screenshot({path: path.join(evidence, 'chat-project.png')});
   log('PASS project: read-only function round-trip with the thought signature;', projectActivity);

   // editor actions
   await page.evaluate(() => {
      const editor = window.rstudio.documents.activeEditor();
      const Range = window.require('ace/range').Range;
      editor.selection.setRange(new Range(2, 0, 3, 40));
   });
   await page.locator('#superr_chat_ai_editor_actions').selectOption('quote');
   assert.match(await page.locator('#superr_chat_ai_prompt').inputValue(), /^```r\nlibrary\(ggplot2\)/);
   await page.locator('#superr_chat_ai_prompt').fill('');
   await page.locator('#superr_chat_ai_context').selectOption('general');
   const answers = await page.locator('[id^="superr_chat_ai_answer_"]').count();
   await page.locator('#superr_chat_ai_editor_actions').selectOption('explain-selection');
   await page.waitForFunction(n => document.querySelectorAll('[id^="superr_chat_ai_answer_"]').length > n, answers, {timeout: 30000});
   await waitState(page, /Gemini conectado|Gemini connected/, 60000);
   assert.equal(await page.locator('#superr_chat_ai_context').inputValue(), 'file', 'Explain selection did not switch to the current file');
   assert.match((await lastActivity(page)).join(' '), /02-graficos\.R/);
   log('PASS editor actions: selection quoted into the prompt; Explain selection sent the file with its selection');

   // quota exhausted in the middle of a read: the files already read are still reported
   await page.locator('#superr_chat_ai_context').selectOption('project');
   await ask(page, 'cuota: analizá el proyecto', /Cuota agotada|Quota exhausted/);
   assert.match((await lastActivity(page)).join(' '), /R\/01-cargar\.R/);
   await waitStatus(page, /límite diario|daily request limit/);
   log('PASS quota error during a read is reported with the files already read');

   // project roots outside the open project, the home folder or a drive root are refused
   const refused = await page.evaluate(async () => {
      const send = root => window.desktop.superrChatSend('gemini-api', 'x', 'gemini-3.6-flash', 'r' + Math.random().toString(36).slice(2, 8),
         { mode: 'project', projectRoot: root, open: [] });
      return [await send('C:/'), await send('~'), await send('C:/Windows')];
   });
   assert.deepEqual(refused.map(r => r.detail), ['invalid_project', 'home_folder', 'invalid_project']);
   log('PASS refused roots: drive root, home folder, a folder without .Rproj');
   await page.evaluate(() => window.rstudio.documents.closeAllNoSave());
}

async function real(page)
{
   await waitState(page, /Gemini conectado|Gemini connected/, 60000);
   await page.locator('#superr_chat_ai_context').selectOption('project');
   await page.locator('#superr_chat_ai_prompt').fill('Analizá los scripts de este proyecto y explicame brevemente qué hace cada uno.');
   await page.locator('#superr_chat_ai_prompt').press('Enter');
   await page.waitForFunction(() => document.querySelectorAll('[id^="superr_chat_ai_answer_"]').length > 0, null, {timeout: 30000});
   await page.waitForFunction(() => !/Generando|Generating/i.test(document.querySelector('#superr_chat_ai_state')?.textContent || ''),
      null, {timeout: 240000});
   await waitState(page, /Gemini conectado|Gemini connected|Cuota|Quota|Error|Sin conexión|Offline/, 60000);
   const state = await page.locator('#superr_chat_ai_state').innerText();
   const activity = await lastActivity(page);
   const answer = await lastAnswer(page).innerText();
   await page.screenshot({path: path.join(evidence, 'chat-project-real.png')});
   log(`state: ${state}; status: ${await page.locator('#superr_chat_ai_status').innerText()}`);
   log(`activity: ${activity.join(' | ')}`);
   log(`answer (${answer.length} characters):\n${answer}`);
   assert.match(state, /Gemini conectado|Gemini connected/);
   assert.ok(activity.length > 0, 'Gemini did not read any project file');
   assert.match(answer, /01-cargar|02-graficos/);
   log('PASS real Gemini project analysis');
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
   await page.waitForFunction(() => /pesquerias/.test(document.title), null, {timeout: 60000}).catch(() => {});
   await page.locator('#superr_chat_ai_toggle').click();
   try { if (mode === 'chat-real-project') await real(page); else await simulated(page); }
   finally {
      // never leave a modified test document behind: it would block the desktop from quitting
      await page.evaluate(() => window.rstudio.documents.closeAllNoSave()).catch(() => {});
   }
   await browser.close();
})().catch(e => { console.error(e); process.exit(1); }); // exit: an open CDP connection would keep node alive
