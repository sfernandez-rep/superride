// Live desktop acceptance test for the Chat IA panel's GWT <-> Electron bridge.
// SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario chat (desktop
// with -Experimental -Automation). Opens the panel and checks, through the real
// preload IPC: provider status, rejection of an unknown provider, the
// Gemini/Codex selector, that personal Google sign-in is not offered, that a
// message is refused while agent isolation is unverified, and that Stop reports
// no active turn. No agent process is started and no account is used.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');

const project = path.resolve(__dirname, '../..');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const status = page => page.locator('#superr_chat_ai_status');
const waitStatus = (page, pattern) => page.waitForFunction(
   source => new RegExp(source, 'i').test(document.querySelector('#superr_chat_ai_status')?.textContent || ''),
   pattern.source, {timeout: 30000});

(async () => {
   const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
   let page;
   for (let i = 0; i < 60 && !page; i++)
   {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(r => setTimeout(r, 1000));
   }
   assert.ok(page, 'no desktop page');
   await page.locator('#superr_chat_ai_toggle').waitFor({timeout: 120000});
   await page.locator('#superr_chat_ai_toggle').click();
   await waitStatus(page, /not verified|sin verificar/);

   const gemini = await page.evaluate(() => window.desktop.superrChatStatus('gemini'));
   assert.equal(gemini.provider, 'gemini');
   assert.equal(gemini.readOnlyAvailable, false);
   const invalid = await page.evaluate(async () => {
      try { await window.desktop.superrChatStatus('invalid'); return false; } catch { return true; }
   });
   assert.equal(invalid, true, 'unknown provider accepted');
   const google = await page.evaluate(async () => {
      try { await window.desktop.superrChatSignIn('gemini'); return 'accepted'; } catch (e) { return String(e); }
   });
   assert.match(google, /not offered/);
   await page.locator('#superr_chat_ai_sign_in').click();
   await waitStatus(page, /terms|términos/);
   await page.screenshot({path: path.join(evidence, 'chat-gemini.png')});

   await page.locator('#superr_chat_ai_provider').selectOption({label: 'Codex'});
   await waitStatus(page, /Signed out|Sin iniciar sesión|Account connected|Cuenta conectada/);
   await page.locator('#superr_chat_ai_prompt').fill('Hello');
   await page.locator('#superr_chat_ai_send').click();
   await waitStatus(page, /not verified|sin verificar/);
   await page.locator('#superr_chat_ai_cancel').click();
   await waitStatus(page, /No response|No hay ninguna/);
   console.log('status:', await status(page).innerText());
   await page.locator('#superr_chat_ai_close').click();
   console.log('PASS real desktop IPC: status, invalid provider, Google sign-in not offered, provider switch, blocked send, no active turn');
   await browser.close();
})().catch(e => { console.error(e); process.exitCode = 1; });
