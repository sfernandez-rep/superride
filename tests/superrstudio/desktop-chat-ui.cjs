// Live desktop test of the Chat IA panel's interface (phase 1), against the
// SIMULATED Gemini API in tests/superrstudio/fixtures/fake-gemini.cjs.
// SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario chat-ui. The
// desktop is real (GWT -> preload IPC -> Electron main -> HTTP); only the
// server answering is fake, so no Google quota is used. Covers: connection
// states, the hidden setup once connected, model choice kept, Enter /
// Shift+Enter, Send and Stop visibility, Markdown rendering (headings, lists,
// table, code with R highlighting, safe links, HTML shown as text), copy and
// insert into the editor with undo, cancel, New conversation during an answer,
// a 429 with Google's quota details, a retired model, the draft kept when the
// panel closes, and screenshots in light and dark themes at two widths.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');

const project = path.resolve(__dirname, '../..');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const KEY = 'AIzaFakeSuperRGuiTestKey000000000000';
const log = (...args) => console.log(...args);
const text = (page, selector) => page.locator(selector).innerText();
const waitState = (page, pattern, timeout = 30000) => page.waitForFunction(
   source => new RegExp(source, 'i').test(document.querySelector('#superr_chat_ai_state')?.textContent || ''),
   pattern.source, {timeout});
const waitStatus = (page, pattern, timeout = 30000) => page.waitForFunction(
   source => new RegExp(source, 'i').test(document.querySelector('#superr_chat_ai_status')?.textContent || ''),
   pattern.source, {timeout});
const visible = (page, selector) => page.locator(selector).isVisible();
const lastAnswer = page => page.locator('[id^="superr_chat_ai_answer_"]').last();

async function ask(page, message)
{
   await page.locator('#superr_chat_ai_prompt').fill(message);
   await page.locator('#superr_chat_ai_prompt').press('Enter');
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

   // not configured: setup shown, Send disabled, Stop hidden
   await waitState(page, /Sin configurar|Not configured/);
   assert.ok(await visible(page, '#superr_chat_ai_gemini_setup'));
   assert.equal(await visible(page, '#superr_chat_ai_cancel'), false, 'Stop visible while idle');
   assert.equal(await page.locator('#superr_chat_ai_send').isDisabled(), true);

   // connect: checking, then connected; setup hidden; models listed
   await page.locator('#superr_chat_ai_key').fill(KEY);
   await page.locator('#superr_chat_ai_save_key').click();
   await waitState(page, /Gemini conectado|Gemini connected/);
   assert.equal(await visible(page, '#superr_chat_ai_gemini_setup'), false, 'setup still shown when connected');
   assert.deepEqual(await page.locator('#superr_chat_ai_model option').evaluateAll(o => o.map(x => x.value)),
      ['gemini-3.6-flash', 'gemini-3.5-flash-lite']);
   await page.locator('#superr_chat_ai_manage').click();
   assert.ok(await visible(page, '#superr_chat_ai_gemini_setup'));
   assert.match(await text(page, '#superr_chat_ai_save_key'), /Cambiar clave|Change key/);
   await page.locator('#superr_chat_ai_manage').click();
   assert.equal(await visible(page, '#superr_chat_ai_gemini_setup'), false);
   await page.locator('#superr_chat_ai_model').selectOption('gemini-3.5-flash-lite');
   assert.equal(await page.evaluate(() => localStorage.getItem('superr.chatIa.geminiModel')), 'gemini-3.5-flash-lite');
   log('PASS states: not configured -> checking -> connected; setup hidden; manage toggles "Change key"; model kept');

   // Shift+Enter is a new line; Enter sends; Stop only while generating
   await page.locator('#superr_chat_ai_prompt').fill('markdown');
   await page.locator('#superr_chat_ai_prompt').press('Shift+Enter');
   await page.locator('#superr_chat_ai_prompt').type('por favor');
   assert.equal(await page.locator('#superr_chat_ai_prompt').inputValue(), 'markdown\npor favor');
   await page.locator('#superr_chat_ai_prompt').press('Enter');
   await waitState(page, /Generando|Generating/);
   assert.ok(await visible(page, '#superr_chat_ai_cancel'), 'Stop hidden while generating');
   assert.equal(await visible(page, '#superr_chat_ai_send'), false);
   await waitState(page, /Gemini conectado|Gemini connected/);
   assert.equal(await visible(page, '#superr_chat_ai_cancel'), false);
   assert.equal(await page.locator('#superr_chat_ai_prompt').inputValue(), '');

   const answer = lastAnswer(page);
   const dom = await answer.evaluate(node => ({
      headings: node.querySelectorAll('h3, h4, h5').length,
      strong: [...node.querySelectorAll('strong')].map(n => n.textContent),
      em: node.querySelectorAll('em').length,
      nested: node.querySelectorAll('ul ul li').length,
      ordered: node.querySelectorAll('ol li').length,
      th: [...node.querySelectorAll('th')].map(n => n.textContent),
      links: [...node.querySelectorAll('.superr-md-link')].map(n => n.title),
      scripts: node.querySelectorAll('script, b, iframe, a[href]').length,
      literal: node.textContent.includes('<script>window.superrInjected = true</script>') && node.textContent.includes('<b>no negrita</b>'),
      code: [...node.querySelectorAll('.superr-md-code-lang')].map(n => n.textContent),
      tokens: node.querySelectorAll('.superr-tok-function, .superr-tok-comment, .superr-tok-operator').length,
      quote: node.querySelectorAll('blockquote').length,
      raw: /\*\*|###|```/.test(node.textContent),
   }));
   assert.equal(dom.headings, 1);
   assert.deepEqual(dom.strong, ['media aritmética']);
   assert.equal(dom.em, 1);
   assert.equal(dom.nested, 1);
   assert.equal(dom.ordered, 2);
   assert.deepEqual(dom.th, ['Función', 'Uso']);
   assert.deepEqual(dom.links, ['https://stat.ethz.ch/R-manual/R-devel/library/base/html/mean.html'], 'unsafe link rendered');
   assert.equal(dom.scripts, 0, 'HTML from the answer became elements');
   assert.equal(dom.literal, true, 'HTML from the answer not shown as text');
   assert.equal(await page.evaluate(() => window.superrInjected), undefined);
   assert.deepEqual(dom.code, ['r']);
   assert.ok(dom.tokens >= 5, 'R code not highlighted');
   assert.equal(dom.quote, 1);
   assert.equal(dom.raw, false, 'Markdown markers shown literally');
   await page.screenshot({path: path.join(evidence, 'chat-ui-light.png')});
   log('PASS Markdown: heading, bold, italic, nested and ordered lists, table, safe link only, HTML as text, R highlighting, quote');

   // copy, insert without a script, insert into a script and undo
   await answer.locator('.superr-md-copy').click();
   await waitStatus(page, /copiado|copied/);
   await answer.locator('.superr-md-insert').click();
   await waitStatus(page, /Abre un script|Open a script/);
   await page.evaluate(() => window.rstudio.commands.newSourceDoc());
   await page.waitForFunction(() => window.rstudio.documents.activeEditor());
   await page.evaluate(() => window.rstudio.documents.activeEditor().setValue('# mi script\n', 1));
   await answer.locator('.superr-md-insert').click();
   await waitStatus(page, /insertado|inserted/);
   const inserted = await page.evaluate(() => window.rstudio.documents.activeEditor().getValue());
   assert.match(inserted, /# mi script\n[\s\S]*mean\(x, na.rm = TRUE\)/);
   await page.evaluate(() => window.rstudio.documents.activeEditor().undo());
   assert.equal(await page.evaluate(() => window.rstudio.documents.activeEditor().getValue()), '# mi script\n');
   await page.evaluate(() => window.rstudio.documents.closeAllNoSave());
   log('PASS code actions: copy; insert needs a script; insert at the cursor; undo removes it');

   // Stop during an answer
   await ask(page, 'respuesta lenta');
   await waitState(page, /Generando|Generating/);
   await page.waitForFunction(() => /palabra 3/.test([...document.querySelectorAll('[id^="superr_chat_ai_answer_"]')].pop()?.textContent || ''));
   await page.locator('#superr_chat_ai_cancel').click();
   await waitStatus(page, /detenida|stopped/);
   await waitState(page, /Gemini conectado|Gemini connected/);
   assert.equal(await visible(page, '#superr_chat_ai_cancel'), false);
   log('PASS Stop cancels a streaming answer and the state returns to connected');

   // New conversation during an answer: cleared, cancelled, still connected, history reset
   await ask(page, 'otra respuesta lenta');
   await waitState(page, /Generando|Generating/);
   await page.locator('#superr_chat_ai_new').click();
   await waitState(page, /Gemini conectado|Gemini connected/);
   assert.equal(await page.locator('[id^="superr_chat_ai_answer_"]').count(), 0);
   await ask(page, 'hola');
   await waitState(page, /Gemini conectado|Gemini connected/);
   assert.match(await lastAnswer(page).innerText(), /turnos: 1\)/, 'history not reset by New conversation');
   log('PASS New conversation cancels, clears, keeps the key and connection, and resets the history');

   // quota and retired model
   await ask(page, 'cuota');
   await waitState(page, /Cuota agotada|Quota exhausted/);
   const quota = await text(page, '#superr_chat_ai_status');
   assert.match(quota, /por minuto|per-minute/);
   assert.match(quota, /: 5\)/);
   assert.match(quota, /17 s/);
   await ask(page, 'modelo retirado');
   await waitStatus(page, /ya no está disponible|no longer available/);
   await waitState(page, /Gemini conectado|Gemini connected/);
   log('PASS 429 shows the scope, limit and retry delay that the server returned; a retired model is reported');

   // the draft survives closing and reopening the panel
   await page.locator('#superr_chat_ai_prompt').fill('borrador sin enviar');
   await page.locator('#superr_chat_ai_close').click();
   await page.locator('#superr_chat_ai_toggle').click();
   assert.equal(await page.locator('#superr_chat_ai_prompt').inputValue(), 'borrador sin enviar');
   await page.locator('#superr_chat_ai_prompt').fill('');
   log('PASS draft kept across close and reopen');

   // other providers show their own state
   await page.locator('#superr_chat_ai_provider').selectOption('codex');
   await waitStatus(page, /Codex:/);
   assert.equal(await visible(page, '#superr_chat_ai_model'), false);
   assert.equal(await page.locator('#superr_chat_ai_send').isDisabled(), true);
   await page.locator('#superr_chat_ai_provider').selectOption('gemini-api');
   await waitState(page, /Gemini conectado|Gemini connected/);
   log('PASS Codex shows its own state; Gemini API restored');

   // screenshots: dark theme, narrow and wide sidebar
   await ask(page, 'markdown');
   await waitState(page, /Gemini conectado|Gemini connected/);
   const panel = page.locator('#superr_chat_ai_panel');
   const shot = async name => panel.screenshot({path: path.join(evidence, `chat-ui-${name}.png`)});
   await shot('light-wide');
   await page.locator('#rstudio_superrstudio_theme_toggle').click();
   await page.waitForFunction(() => document.getElementById('rstudio_container').classList.contains('rstudio-themes-dark'), null, {timeout: 30000});
   await page.waitForTimeout(500);
   await shot('dark-wide');
   // drag the sidebar splitter: wider, then narrow
   const drag = async to => {
      const box = await panel.boundingBox();
      const y = box.y + box.height / 2;
      // the splitter is the element left of the panel with a resize cursor
      const x = await page.evaluate(([left, top]) => {
         for (let dx = 1; dx <= 12; dx++) {
            const node = document.elementFromPoint(left - dx, top);
            if (node && /resize/.test(getComputedStyle(node).cursor)) return left - dx;
         }
         return left - 3;
      }, [box.x, y]);
      await page.mouse.move(x, y);
      await page.mouse.down();
      await page.mouse.move(to(box), box.y + box.height / 2, {steps: 10});
      await page.mouse.up();
      await page.waitForTimeout(600);
      return Math.round((await panel.boundingBox()).width);
   };
   const wide = await drag(box => box.x - 260);
   await shot('dark-wider');
   const narrow = await drag(box => box.x + box.width - 250);
   log(`sidebar width: wide ${wide} px, narrow ${narrow} px`);
   assert.ok(wide > narrow + 150, 'the splitter did not resize the panel');
   await shot('dark-narrow');
   await page.locator('#rstudio_superrstudio_theme_toggle').click();
   await page.waitForFunction(() => !document.getElementById('rstudio_container').classList.contains('rstudio-themes-dark'), null, {timeout: 30000});
   await page.waitForTimeout(500);
   await shot('light-narrow');
   log('PASS screenshots in light and dark themes, wide and narrow');
   await browser.close();
})().catch(e => { console.error(e); process.exit(1); }); // exit: an open CDP connection would keep node alive
