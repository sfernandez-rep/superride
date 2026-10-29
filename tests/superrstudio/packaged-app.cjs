// Acceptance test of the *installed* SuperR application, driven over the
// Chromium debugging port. SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-packaged.ps1, which installs the
// installer, opens a copy of the synthetic RStudio project
// (tests/superrstudio/fixtures/rstudio-project) and launches SuperR.exe three
// times:
//   nopkg    first start with an empty user library: the optional-package
//            dialog for ggplot2, Cancel, the IDE stays usable
//   first    features on: branding, R discovery, project, script with
//            relative paths, CSV/RDS/RData, ggplot2, plot editor docked and
//            floating, export, length-frequency window, theme switch; then
//            selects Spanish for the restart
//   restart  the same profile: project, layout, theme and language restored;
//            Spanish windows; back to English and light
//   off      SUPER_RSTUDIO_EXPERIMENTAL=0: the IDE without SuperR features
//
//   node tests/superrstudio/packaged-app.cjs <phase> <project copy> <evidence dir>
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const phase = process.argv[2];
const projectDir = path.resolve(process.argv[3]).replaceAll('\\', '/');
const evidence = path.resolve(process.argv[4]);
fs.mkdirSync(evidence, {recursive: true});
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19391';
const results = [];
const log = (...args) => console.log(...args);
const pass = (name, detail = '') => { results.push({phase, name, result: 'PASS', detail}); log('PASS', name, detail); };
const expect = (condition, message) => { if (!condition) throw new Error(message); };
const shot = (page, name) => page.screenshot({path: path.join(evidence, `packaged-${phase}-${name}.png`)});

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
   await page.waitForFunction(n => window.rstudio.console.promptCount > n, before, {timeout: 120000});
}

// Run R code printing `<marker> <value>`; returns the value.
async function value(page, expression, marker)
{
   await run(page, `cat('${marker}', ${expression}, '\\n', sep = '|')`);
   const text = await page.locator('#rstudio_workbench_panel_console').innerText();
   const match = [...text.matchAll(new RegExp(marker + '\\|(.*)\\|', 'g'))].pop();
   if (!match) throw new Error(`no output for ${marker}:\n${text.slice(-2000)}`);
   return match[1];
}

async function reveal(page, selector)
{
   await page.evaluate(selector => {
      const panel = document.querySelector(selector)?.closest('[data-superrstudio-tab]');
      const tab = panel && document.getElementById('superrstudio_tab_' + panel.getAttribute('data-superrstudio-tab'));
      if (tab && tab.getAttribute('aria-selected') !== 'true') tab.click();
   }, selector);
}
const choose = async (page, selector, v) => { await reveal(page, selector); return page.selectOption(selector, v); };
const waitCode = (page, source) => page.waitForFunction(s => new RegExp(s).test(document.getElementById('superrstudio_code')?.value || ''),
                                                        source, {timeout: 60000});
const waitStatus = (page, source) => page.waitForFunction(s => new RegExp(s).test(document.getElementById('superrstudio_status')?.innerText || ''),
                                                          source, {timeout: 60000});
const visible = (page, id) => page.evaluate(id => { const e = document.getElementById(id); return !!e && e.offsetParent !== null; }, id);
const dark = page => page.evaluate(() => document.getElementById('rstudio_container').classList.contains('rstudio-themes-dark'));
const waitDark = (page, d) => page.waitForFunction(d => document.getElementById('rstudio_container').classList.contains('rstudio-themes-dark') === d,
                                                   d, {timeout: 30000});

async function common(page)
{
   // the window title is checked by test-packaged.ps1 (the Electron window
   // title; the page's own title is not shown in the desktop)
   const r = await value(page, 'R.version.string', 'SRV');
   expect(/^R version \d+\.\d+\.\d+/.test(r), 'R version: ' + r);
   pass('R discovered and running', r);
   const project = await value(page, "normalizePath(.rs.getProjectDirectory(), winslash = '/')", 'SRP');
   expect(project.toLowerCase() === projectDir.toLowerCase(), `project ${project}, expected ${projectDir}`);
   const wd = await value(page, "normalizePath(getwd(), winslash = '/')", 'SRW');
   expect(wd.toLowerCase() === projectDir.toLowerCase(), 'working directory ' + wd);
   pass('RStudio project (.Rproj) open, working directory at the project', project);
}

(async () => {
   const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
   let page;
   for (let i = 0; i < 180 && !page; i++)
   {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(resolve => setTimeout(resolve, 1000));
   }
   if (!page) throw new Error('SuperR window did not load');
   await page.waitForFunction(() => window.rstudio?.ready, null, {timeout: 180000});
   await page.waitForTimeout(2000);
   const errorsAtStart = await page.evaluate(() => window.rstudio.errors.list());
   expect(!errorsAtStart.length, 'client exceptions at start-up: ' + JSON.stringify(errorsAtStart));
   await common(page);

   if (phase === 'nopkg')
   {
      // first start without optional packages: the IDE works, the plot editor
      // asks before installing ggplot2, Cancel installs nothing
      const gg = await value(page, "nzchar(system.file(package = 'ggplot2', lib.loc = .libPaths()))", 'SRN');
      expect(gg === 'FALSE', 'ggplot2 found in the empty library setup');
      await page.evaluate(() => window.rstudio.commands.activateEnvironment());
      await page.locator('#rstudio_superrstudio_scatter').click();
      await page.locator('#superrstudio_deps_dialog').waitFor({timeout: 60000});
      await page.waitForFunction(() => /Library: /.test(document.getElementById('superrstudio_deps_details')?.innerText || ''),
                                 null, {timeout: 120000});
      const details = await page.locator('#superrstudio_deps_details').innerText();
      expect(details.includes('ggplot2 3.4.0 or newer: not installed'), 'dependency dialog: ' + details);
      await shot(page, '1-dependency-prompt');
      await page.locator('#rstudio_superrstudio_deps_cancel').click();
      await page.locator('#superrstudio_deps_dialog').waitFor({state: 'detached'});
      await page.locator('#superrstudio_deps_hint').waitFor();
      const sum = await value(page, 'sum(1:10)', 'SRQ');
      expect(sum === '55', 'console after cancel: ' + sum);
      pass('first start without optional packages: prompt names ggplot2, Cancel installs nothing, IDE usable');
   }
   else if (phase === 'first')
   {
      await shot(page, '1-start');
      await run(page, "source('R/analysis.R')");
      const out = await value(page, "paste(nrow(merged), nrow(summary_by_species), file.exists('output/summary.csv'), " +
                                    "file.exists('output/merged.rds'), file.exists('output/length-weight.png'))", 'SRA');
      expect(out === '12 3 TRUE TRUE TRUE', 'analysis outputs: ' + out);
      pass('script with relative paths: CSV, RDS and RData read; CSV, RDS and ggplot2 PNG written to the copy', out);
      const gg = await value(page, "as.character(utils::packageVersion('ggplot2'))", 'SRG');
      pass('ggplot2 available', gg);
      await run(page, "file.edit('report.Rmd'); file.edit('notes.qmd'); file.edit('R/analysis.R')");
      await page.waitForTimeout(3000);
      const tabs = await page.evaluate(() => [...document.querySelectorAll('.gwt-TabLayoutPanelTab')].map(t => t.innerText.trim()));
      expect(['report.Rmd', 'notes.qmd', 'analysis.R'].every(n => tabs.some(t => t.includes(n))), 'editor tabs: ' + tabs);
      pass('R Markdown, Quarto and R script opened in the editor', tabs.filter(t => /\.(Rmd|qmd|R)$/.test(t)).join(', '));

      // plot editor docked in the Visual tab, then floating and docked again
      await page.evaluate(() => window.rstudio.commands.activateVisual());
      await page.waitForFunction(() => document.querySelector('#superrstudio_visual_host #superrstudio_dataset'), null, {timeout: 60000});
      await page.waitForFunction(() => [...document.getElementById('superrstudio_dataset').options].some(o => o.value === 'merged'));
      await choose(page, '#superrstudio_dataset', 'merged');
      await page.waitForFunction(() => [...document.getElementById('superrstudio_x').options].some(o => o.value === 'length_cm'));
      await choose(page, '#superrstudio_x', 'length_cm');
      await choose(page, '#superrstudio_y', 'weight_g');
      await choose(page, '#superrstudio_fit', 'lm');
      await waitCode(page, 'ggplot2::geom_point\\(\\)');
      await page.waitForFunction(() => document.querySelector('#superrstudio_visual_host #superrstudio_interactive img')?.src,
                                 null, {timeout: 60000});
      const code = await page.locator('#superrstudio_code').inputValue();
      expect(code.includes('ggplot2::ggplot(merged, ') && code.includes('method = "lm"'), 'generated code: ' + code);
      await shot(page, '2-visual-docked');
      pass('plot editor docked in the Visual tab: preview and ggplot2 code with lm fit');
      await page.locator('#rstudio_superrstudio_float').click();
      await page.getByRole('dialog').waitFor();
      expect(await page.locator('#superrstudio_code').inputValue() === code, 'state lost when floating');
      await shot(page, '3-visual-floating');
      // export from the floating editor into the project copy
      const exportPath = projectDir + '/output/editor-plot.png';
      await choose(page, '#superrstudio_export_format', 'png');
      await reveal(page, '#superrstudio_export_path');
      await page.fill('#superrstudio_export_path', exportPath);
      await page.locator('#superrstudio_export_image').click();
      await waitStatus(page, '^Saved .+editor-plot\\.png');
      expect(fs.existsSync(exportPath), 'exported file missing: ' + exportPath);
      pass('export PNG from the plot editor', exportPath);
      await page.locator('#rstudio_superrstudio_dock').click();
      await page.getByRole('dialog').waitFor({state: 'detached'});
      await page.waitForFunction(() => document.querySelector('#superrstudio_visual_host #superrstudio_dataset'));
      pass('float and dock again keep the editor state');
      // the generated code runs as written
      await run(page, 'srs_plot <- eval(parse(text = ' + JSON.stringify(code) + '))[[1]]');
      const cls = await value(page, "paste(class(srs_plot), collapse = ',')", 'SRC');
      expect(cls.includes('ggplot'), 'generated code result: ' + cls);
      pass('generated ggplot2 code evaluates to a ggplot object');

      // length-frequency window (needs TropFishR in the library)
      const tropfishr = await value(page, "requireNamespace('TropFishR', quietly = TRUE)", 'SRT');
      await page.evaluate(() => window.rstudio.commands.activateEnvironment());
      await page.locator('#rstudio_superrstudio_lfq').waitFor({state: 'visible', timeout: 30000});
      await page.locator('#rstudio_superrstudio_lfq').click();
      await page.locator('#superrstudio_lfq_status').waitFor();
      await page.waitForTimeout(3000);
      const lfqStatus = await page.locator('#superrstudio_lfq_status').innerText();
      if (tropfishr === 'TRUE') expect(/TropFishR \d/.test(lfqStatus), 'LFQ status: ' + lfqStatus);
      await shot(page, '4-lfq');
      await page.keyboard.press('Escape');
      await page.waitForTimeout(1000);
      pass('length-frequency window opens', `TropFishR available: ${tropfishr}; ${lfqStatus.split('\n')[0]}`);

      // one-click theme switch to dark, remembered at the restart
      expect(!(await dark(page)), 'starts dark');
      await page.locator('#rstudio_superrstudio_theme_toggle').click();
      await waitDark(page, true);
      await page.waitForTimeout(1500);
      await shot(page, '5-dark');
      pass('theme switch: dark theme applied');
      // Spanish for the SuperR windows at the next start
      await run(page, ".rs.writeUiPref('ui_language', 'es')");
      pass('Spanish selected for the restart');
   }
   else if (phase === 'restart')
   {
      expect(await dark(page), 'dark theme not remembered');
      pass('dark theme remembered after restart');
      expect(await visible(page, 'rstudio_workbench_tab_visual'), 'Visual tab not restored');
      pass('Visual tab restored in the pane layout');
      const label = await page.locator('#rstudio_superrstudio_scatter').innerText().catch(() => '');
      expect(label.includes('Editor de gráficos'), 'plot editor button not in Spanish: ' + label);
      pass('Spanish: SuperR windows follow ui_language "es"', label.trim());
      await shot(page, '1-restart-dark-es');
      await run(page, ".rs.writeUiPref('ui_language', 'en')");
      await page.locator('#rstudio_superrstudio_theme_toggle').click();
      await waitDark(page, false);
      pass('back to English (next start) and light theme');
   }
   else if (phase === 'off')
   {
      expect(!(await visible(page, 'rstudio_workbench_tab_visual')), 'Visual tab shown with features off');
      expect(!(await page.locator('#rstudio_superrstudio_theme_toggle').count()), 'theme toggle shown with features off');
      await page.evaluate(() => window.rstudio.commands.activateEnvironment());
      await page.waitForTimeout(2000);
      expect(!(await page.locator('#rstudio_superrstudio_scatter').isVisible()), 'plot editor button shown with features off');
      const sum = await value(page, 'sum(1:10)', 'SRS');
      expect(sum === '55', 'console: ' + sum);
      await shot(page, '1-off');
      pass('features off (SUPER_RSTUDIO_EXPERIMENTAL=0): no Visual tab, toolbar switch or editor buttons; IDE works');
   }
   const errors = await page.evaluate(() => window.rstudio.errors.list());
   expect(!errors.length, 'client exceptions: ' + JSON.stringify(errors));
   fs.writeFileSync(path.join(evidence, `packaged-${phase}.json`), JSON.stringify(results, null, 1));
})().catch(error => {
   console.error('FAIL', error.message);
   results.push({phase, name: 'error', result: 'FAIL', detail: error.message});
   fs.writeFileSync(path.join(evidence, `packaged-${phase}.json`), JSON.stringify(results, null, 1));
   process.exitCode = 1;
}).finally(() => process.exit());
