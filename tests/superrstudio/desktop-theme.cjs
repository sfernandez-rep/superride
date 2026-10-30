// Live desktop acceptance test for the one-click light/dark theme switch.
// SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario theme, which
// launches one isolated profile three times:
//   first    experimental; keyboard toggle to dark and back; a custom dark
//            theme (Cobalt) chosen elsewhere is remembered by the toggle;
//            the profile is left in Cobalt
//   restart  experimental; Cobalt is still applied after the restart; the
//            toggle switches to light
//   off      features disabled: no toggle in the toolbar
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const phase = process.argv[2];
const project = path.resolve(__dirname, '../..').replaceAll('\\', '/');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
fs.mkdirSync(evidence, {recursive: true});
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const log = (...args) => console.log(...args);
const shot = (page, name) => page.screenshot({path: path.join(evidence, `theme-${phase}-${name}.png`)});
const expect = (condition, message) => { if (!condition) throw new Error(message); };

async function run(page, command)
{
   const before = await page.evaluate(text => {
      window.rstudio.commands.activateConsole();
      const editor = document.getElementById('rstudio_console_input').env.editor;
      editor.setValue(text, 1);
      editor.focus();
      return window.rstudio.console.promptCount;
   }, command);
   await page.keyboard.press('Enter');
   await page.waitForFunction(n => window.rstudio.console.promptCount > n, before, {timeout: 60000});
}

const state = page => page.evaluate(() => {
   const toggle = document.getElementById('rstudio_superrstudio_theme_toggle');
   return {dark: document.getElementById('rstudio_container').classList.contains('rstudio-themes-dark'),
           pref: window.rstudio.prefs.editorTheme.get(), toggle: !!toggle,
           label: toggle ? toggle.getAttribute('aria-label') : '', title: toggle ? toggle.title : ''};
});
const waitDark = (page, dark) => page.waitForFunction(d =>
   document.getElementById('rstudio_container').classList.contains('rstudio-themes-dark') === d, dark, {timeout: 30000});
// a click or key changes the applied theme, then the preference is written
const waitPref = (page, name) => page.waitForFunction(n => window.rstudio.prefs.editorTheme.get() === n, name,
                                                      {timeout: 30000});

(async () => {
   const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
   let page;
   for (let i = 0; i < 120 && !page; i++)
   {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(resolve => setTimeout(resolve, 1000));
   }
   if (!page) throw new Error('RStudio window did not load');
   await page.waitForFunction(() => window.rstudio?.ready, null, {timeout: 120000});
   await page.waitForTimeout(1500);
   await page.evaluate(() => window.rstudio.errors.clear());
   let s = await state(page);
   log(phase, 'at start:', JSON.stringify(s));

   if (phase === 'off')
   {
      expect(!s.toggle, 'theme toggle shown with features disabled');
      log('PASS features off: no theme toggle; theme', s.pref);
   }
   else if (phase === 'first')
   {
      expect(s.toggle && !s.dark && s.label === 'Switch to the dark theme (Tomorrow Night)' && s.title === s.label,
             'initial toggle state: ' + JSON.stringify(s));
      await shot(page, '1-light');
      // keyboard: focus and Enter
      await page.focus('#rstudio_superrstudio_theme_toggle');
      await page.keyboard.press('Enter');
      await waitDark(page, true);
      await waitPref(page, 'Tomorrow Night');
      s = await state(page);
      expect(s.label === 'Switch to the light theme (Textmate (default))', 'label in dark mode: ' + s.label);
      const focusRing = await page.evaluate(() => {
         const toggle = document.getElementById('rstudio_superrstudio_theme_toggle');
         toggle.focus();
         return getComputedStyle(toggle).outlineStyle;
      });
      await shot(page, '2-dark');
      log('PASS keyboard toggle to dark (Tomorrow Night); label and tooltip describe the next action; focus outline', focusRing);
      await page.locator('#rstudio_superrstudio_theme_toggle').click();
      await waitDark(page, false);
      await waitPref(page, 'Textmate (default)');
      log('PASS toggle back to light (Textmate)');
      // a custom dark theme chosen through RStudio's own API is remembered
      await run(page, ".rs.api.applyTheme('Cobalt')");
      await waitDark(page, true);
      await page.locator('#rstudio_superrstudio_theme_toggle').click();
      await waitDark(page, false);
      await waitPref(page, 'Textmate (default)');
      s = await state(page);
      expect(s.label === 'Switch to the dark theme (Cobalt)', 'custom dark theme not remembered: ' + s.label);
      await page.locator('#rstudio_superrstudio_theme_toggle').click();
      await waitDark(page, true);
      await waitPref(page, 'Cobalt');
      await page.waitForTimeout(1500);   // the preference and state reach the session
      log('PASS custom dark theme (Cobalt) remembered and restored by the toggle');
   }
   else
   {
      expect(s.dark && s.pref === 'Cobalt' && s.label === 'Switch to the light theme (Textmate (default))',
             'theme not kept after restart: ' + JSON.stringify(s));
      await shot(page, '1-restored');
      await page.locator('#rstudio_superrstudio_theme_toggle').click();
      await waitDark(page, false);
      await waitPref(page, 'Textmate (default)');
      s = await state(page);
      expect(s.label === 'Switch to the dark theme (Cobalt)', 'remembered dark theme lost after restart: ' + s.label);
      log('PASS theme persisted across the restart (Cobalt); toggle to light; Cobalt still remembered');
   }
   const errors = await page.evaluate(() => window.rstudio.errors.list());
   expect(!errors.length, 'client exceptions: ' + JSON.stringify(errors));
   log(`DESKTOP_THEME_${phase.toUpperCase()}_PASS`);
   await browser.close();
})().catch(async error => {
   console.error(error);
   process.exitCode = 1;
   try
   {
      const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
      const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      console.error('state:', JSON.stringify(await state(page)));
      await shot(page, 'failure');
   }
   catch (e) { console.error('no diagnostics:', e.message); }
}).finally(() => process.exit());
