// Live desktop acceptance test for the Visual workbench tab and pane-layout
// migration. SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario visual, which
// launches the same isolated profile three times:
//   migrate  experimental; the profile holds a pane layout saved before the
//            Visual tab existed (customised: History and Help swapped, no
//            hiddenTabSet/sidebar fields)
//   restart  experimental again; the layout saved by the first launch
//   off      SuperRStudio features disabled with that same saved layout
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const phase = process.argv[2];
const project = path.resolve(__dirname, '../..').replaceAll('\\', '/');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
fs.mkdirSync(evidence, {recursive: true});
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const log = (...args) => console.log(...args);
const shot = (page, name) => page.screenshot({path: path.join(evidence, `visual-${phase}-${name}.png`)});
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

// the visible pane tabs, by their tab set (the panel holding each tab element)
const layout = page => page.evaluate(() => {
   const panes = window.rstudio.prefs.panes.get();
   const visible = id => { const e = document.getElementById(id); return !!e && e.offsetParent !== null; };
   return {panes, visual: visible('rstudio_workbench_tab_visual'),
           history: visible('rstudio_workbench_tab_history'), environment: visible('rstudio_workbench_tab_environment'),
           help: visible('rstudio_workbench_tab_help')};
});
const waitCode = (page, source) => page.waitForFunction(s => new RegExp(s).test(document.getElementById('superrstudio_code')?.value || ''),
                                                        source, {timeout: 60000});

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
   await page.waitForTimeout(2000);
   const errorsAtStart = await page.evaluate(() => window.rstudio.errors.list());
   expect(!errorsAtStart.length, 'client exceptions at start-up: ' + JSON.stringify(errorsAtStart));
   let state = await layout(page);
   log(phase, 'layout at start:', JSON.stringify(state.panes));
   // the customised layout is preserved in every phase
   expect(state.panes.tabSet2.includes('History') && state.panes.tabSet1.includes('Help'),
          'customised pane layout not preserved: ' + JSON.stringify(state.panes));
   expect(state.environment, 'Environment tab missing');

   if (phase === 'off')
   {
      expect(!state.visual, 'Visual tab shown with features disabled');
      expect(!(await page.evaluate(() => window.rstudio.commands.activateVisual.isVisible())), 'activateVisual visible');
      await run(page, 'srs_off <- 1 + 1');
      await page.evaluate(() => window.rstudio.commands.activateEnvironment());
      await page.waitForTimeout(3000);
      expect(!(await page.locator('#rstudio_superrstudio_scatter').isVisible()), 'plot editor button visible');
      await shot(page, '1-off');
      log('PASS features off with a saved layout containing Visual: no tab, no commands, no errors; layout kept');
   }
   else
   {
      if (phase === 'migrate')
      {
         expect(!state.visual, 'Visual tab shown before it was requested (must start hidden)');
         log('PASS old layout migrated: start-up without errors, Visual hidden, customised tabs in place');
      }
      await run(page, 'set.seed(1); visual_data <- data.frame(day = as.Date("2024-01-01") + 0:59, ' +
                      'level = cumsum(rnorm(60)), size = runif(60, 10, 20))');
      // Show Visual: the editor docks into the pane
      await page.evaluate(() => window.rstudio.commands.activateVisual());
      await page.waitForFunction(() => document.querySelector('#superrstudio_visual_host #superrstudio_dataset'),
                                 null, {timeout: 60000});
      state = await layout(page);
      expect(state.visual, 'Visual tab not shown after activation');
      await page.waitForFunction(() => [...document.getElementById('superrstudio_dataset').options].some(o => o.value === 'visual_data'));
      await page.selectOption('#superrstudio_dataset', 'visual_data');
      await page.waitForFunction(() => [...document.getElementById('superrstudio_x').options].some(o => o.value === 'day'));
      await page.selectOption('#superrstudio_x', 'day');
      await page.selectOption('#superrstudio_y', 'level');
      await page.selectOption('#superrstudio_geometry', 'lines');
      await waitCode(page, 'ggplot2::geom_line\\(\\)');
      await page.waitForFunction(() => document.querySelector('#superrstudio_visual_host #superrstudio_interactive img')?.src);
      const docked = await page.locator('#superrstudio_code').inputValue();
      await shot(page, '1-docked');
      log('PASS editor docked in the Visual pane: preview and code rendered');
      // the same editor floats, keeping its state, and docks again
      await page.locator('#rstudio_superrstudio_float').click();
      await page.getByRole('dialog').waitFor();
      expect(await page.locator('#superrstudio_dataset').inputValue() === 'visual_data' &&
             await page.locator('#superrstudio_x').inputValue() === 'day' &&
             await page.locator('#superrstudio_code').inputValue() === docked, 'state lost when floating');
      await page.locator('#superrstudio_visual_dock_here').waitFor({state: 'attached'});
      await shot(page, '2-floating');
      await page.locator('#rstudio_superrstudio_dock').click();
      await page.getByRole('dialog').waitFor({state: 'detached'});
      await page.waitForFunction(() => document.querySelector('#superrstudio_visual_host #superrstudio_dataset'));
      expect(await page.locator('#superrstudio_code').inputValue() === docked, 'state lost when docking again');
      // the toolbar button shows the docked editor instead of a second window
      await page.evaluate(() => window.rstudio.commands.activateEnvironment());
      await page.locator('#rstudio_superrstudio_scatter').click();
      await page.waitForTimeout(1000);
      expect(!(await page.getByRole('dialog').count()), 'toolbar opened a second editor');
      expect((await layout(page)).visual, 'toolbar did not show the Visual pane');
      // zoom and restore through the layout commands
      await page.evaluate(() => window.rstudio.commands.layoutZoomVisual());
      await page.waitForTimeout(1000);
      expect(await page.evaluate(() => window.rstudio.commands.layoutZoomVisual.isChecked()), 'zoom not applied');
      await page.evaluate(() => window.rstudio.commands.layoutEndZoom());
      await page.waitForTimeout(1000);
      await run(page, 'srs_responsive <- sum(1:10)');
      state = await layout(page);
      log(phase, 'layout after use:', JSON.stringify(state.panes));
      log('PASS float and dock keep the same editor state; toolbar shows the pane; zoom works; console responsive');
   }
   const errors = await page.evaluate(() => window.rstudio.errors.list());
   expect(!errors.length, 'client exceptions: ' + JSON.stringify(errors));
   log(`DESKTOP_VISUAL_${phase.toUpperCase()}_PASS`);
   await browser.close();
})().catch(async error => {
   console.error(error);
   process.exitCode = 1;
   try
   {
      const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
      const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      console.error('errors:', JSON.stringify(await page.evaluate(() => window.rstudio?.errors.list())));
      await shot(page, 'failure');
   }
   catch (e) { console.error('no diagnostics:', e.message); }
}).finally(() => process.exit());
