// Live desktop acceptance test for the Chat IA panel's GWT <-> Electron bridge.
// SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario chat (desktop
// with -Experimental -Automation, fresh isolated profile).
//
//   chat       no account needed. Gemini API mode: setup and privacy notice,
//              sending without a key, and a made-up key that is checked by
//              Google for real (API_KEY_INVALID) and never written to the
//              profile or logs. Antigravity: personal Google sign-in not
//              offered. Codex: message refused, Stop reports no active turn.
//   chat-real  the owner has already saved their own AI Studio key in this
//              profile through the panel. Sends the first question to Gemini
//              and waits for a real streamed answer.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const mode = process.argv[2] || 'chat';
const project = path.resolve(__dirname, '../..');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const FAKE_KEY = 'AIzaSuperRInvalidTestKey0000000000000000';
const QUESTION = 'Hola, ¿podés explicarme para qué sirve mean() en R?';
const statusText = page => page.locator('#superr_chat_ai_status').innerText();
const waitStatus = (page, pattern, timeout = 30000) => page.waitForFunction(
   source => new RegExp(source, 'i').test(document.querySelector('#superr_chat_ai_status')?.textContent || ''),
   pattern.source, {timeout});
const waitState = (page, pattern, timeout = 30000) => page.waitForFunction(
   source => new RegExp(source, 'i').test(document.querySelector('#superr_chat_ai_state')?.textContent || ''),
   pattern.source, {timeout});

async function basic(page)
{
   await waitState(page, /Sin configurar|Not configured/);
   assert.ok(await page.locator('#superr_chat_ai_gemini_setup').isVisible(), 'key setup not shown');
   assert.match(await page.locator('#superr_chat_ai_privacy').innerText(), /mejorar sus productos|improve its products/);
   assert.equal(await page.locator('#superr_chat_ai_key').getAttribute('type'), 'password');

   await page.locator('#superr_chat_ai_prompt').fill(QUESTION);
   assert.equal(await page.locator('#superr_chat_ai_send').isDisabled(), true, 'Send enabled without a key');
   const noKey = await page.evaluate(() => window.desktop.superrChatSend('gemini-api', 'x', 'gemini-3.6-flash', 't0'));
   assert.deepEqual(noKey, { status: 'error', kind: 'no_key' });
   await page.locator('#superr_chat_ai_prompt').fill('');

   // real request to Google with a made-up key
   await page.locator('#superr_chat_ai_key').fill(FAKE_KEY);
   await page.locator('#superr_chat_ai_save_key').click();
   await waitStatus(page, /no es válida|not valid/, 60000);
   console.log('real Google check of a made-up key:', await statusText(page));
   const status = await page.evaluate(() => window.desktop.superrChatStatus('gemini-api'));
   assert.equal(status.authentication, 'signed_out');
   await page.screenshot({path: path.join(evidence, 'chat-gemini-api-invalid-key.png')});
   await page.locator('#superr_chat_ai_key').fill('');

   const invalid = await page.evaluate(async () => {
      try { await window.desktop.superrChatStatus('invalid'); return false; } catch { return true; }
   });
   assert.equal(invalid, true, 'unknown provider accepted');
   const paid = await page.evaluate(async () => {
      try { await window.desktop.superrChatSend('gemini-api', 'x', 'gemini-4-argon', 't9'); return 'accepted'; }
      catch (e) { return String(e); }
   });
   assert.match(paid, /Invalid model/, 'a model outside the free list was accepted');

   await page.locator('#superr_chat_ai_provider').selectOption('gemini');
   await waitStatus(page, /not verified|sin verificar/);
   await page.locator('#superr_chat_ai_manage').click();
   assert.match(await page.locator('#superr_chat_ai_agent_setup').innerText(), /terms|términos/);
   const google = await page.evaluate(async () => {
      try { await window.desktop.superrChatSignIn('gemini'); return 'accepted'; } catch (e) { return String(e); }
   });
   assert.match(google, /not offered/);

   await page.locator('#superr_chat_ai_provider').selectOption('codex');
   await waitStatus(page, /Signed out|Sin iniciar sesión|signed out|sin iniciar sesión|Account connected|account connected|Cuenta conectada|cuenta conectada/);
   await page.locator('#superr_chat_ai_prompt').fill('Hello');
   assert.equal(await page.locator('#superr_chat_ai_send').isDisabled(), true, 'Send enabled for Codex');
   const refused = await page.evaluate(async () => {
      try { await window.desktop.superrChatSend('codex', 'Hello', '', ''); return 'accepted'; } catch (e) { return String(e); }
   });
   assert.match(refused, /isolation/);
   const noTurn = await page.evaluate(async () => {
      try { await window.desktop.superrChatCancel('codex'); return 'accepted'; } catch (e) { return String(e); }
   });
   assert.match(noTurn, /No active/);
   await page.locator('#superr_chat_ai_prompt').fill('');
   console.log('PASS real desktop IPC: Gemini API setup, missing key, real invalid-key error, ' +
      'free-model guard, Antigravity sign-in not offered, Codex refused, no active turn');
}

async function real(page)
{
   await waitState(page, /Gemini conectado|Gemini connected/, 60000);
   await page.waitForFunction(() => document.querySelector('#superr_chat_ai_model')?.options.length > 0, null, {timeout: 60000});
   console.log('model:', await page.locator('#superr_chat_ai_model').inputValue());
   await page.locator('#superr_chat_ai_prompt').fill(QUESTION);
   const started = Date.now();
   await page.locator('#superr_chat_ai_prompt').press('Enter');
   const answer = page.locator('[id^="superr_chat_ai_answer_"]').last();
   await page.waitForFunction(() => {
      const nodes = document.querySelectorAll('[id^="superr_chat_ai_answer_"]');
      return nodes.length && nodes[nodes.length - 1].textContent.replace('…', '').trim().length > 0;
   }, null, {timeout: 120000});
   const firstText = Date.now() - started;
   await waitState(page, /Gemini conectado|Gemini connected|Cuota|Quota|Error|Sin conexión|Offline/, 180000);
   const status = await statusText(page);
   const text = await answer.innerText();
   await page.screenshot({path: path.join(evidence, 'chat-gemini-api-real.png')});
   console.log(`status: ${status}`);
   console.log(`first text after ${firstText} ms; answer (${text.length} characters):\n${text}`);
   assert.match(status, /Respuesta recibida|Response received/);
   assert.match(text, /mean/);
   const rendered = await answer.evaluate(n => ({ raw: /\*\*|###|```/.test(n.textContent),
      code: n.querySelectorAll('.superr-md-code').length, strong: n.querySelectorAll('strong').length }));
   console.log('rendered:', JSON.stringify(rendered));
   assert.equal(rendered.raw, false, 'Markdown markers shown literally');
   console.log('PASS real Gemini API conversation');
}

(async () => {
   fs.mkdirSync(evidence, {recursive: true});
   const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
   let page;
   for (let i = 0; i < 60 && !page; i++)
   {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(r => setTimeout(r, 1000));
   }
   assert.ok(page, 'no desktop page');
   await page.locator('#superr_chat_ai_toggle').waitFor({timeout: 120000});
   if (!(await page.locator('#superr_chat_ai_panel').count()) || !(await page.locator('#superr_chat_ai_panel').isVisible()))
      await page.locator('#superr_chat_ai_toggle').click();
   if (mode === 'chat-real') await real(page); else await basic(page);
   await browser.close();
   // test-gui-scatter.ps1 scans the profile for FAKE_KEY after the desktop quits
   // (files are locked while it runs)
})().catch(e => { console.error(e); process.exitCode = 1; });
