// Live desktop acceptance test for the Spanish user interface of SuperRStudio's
// features. SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario es (desktop with
// -Experimental -Automation, ui_language "es" in the isolated profile and the
// isolated library holding ggplot2 and TropFishR). Expected texts are read from
// the Spanish message files, so the test checks what the compiled build shows
// rather than a copy of the translations. Numbers and R code must stay
// unlocalized (decimal point, English R syntax).
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const project = path.resolve(__dirname, '../..').replaceAll('\\', '/');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
fs.mkdirSync(evidence, {recursive: true});
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const log = (...args) => console.log(...args);
const shot = (page, name) => page.screenshot({path: path.join(evidence, `es-${name}.png`)});
const messages = name => Object.fromEntries(fs.readFileSync(path.join(project,
   'src/gwt/src/org/rstudio/studio/client/workbench/views/superrstudio', name), 'utf8')
   .split(/\r?\n/).filter(line => line && !line.startsWith('#') && line.includes('='))
   .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1).replace(/''/g, "'")]));
const sc = messages('ScatterMessages_es.properties');
const lf = messages('LfqMessages_es.properties');
const fill = (pattern, ...args) => pattern.replace(/\{(\d+)\}/g, (_, i) => args[i]);

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

async function check(page, code, marker)
{
   await run(page, `${code}; cat('${marker}\\n')`);
   const output = await page.locator('#rstudio_workbench_panel_console').innerText();
   if (!output.includes(marker + '\n'))
      throw new Error(`R check failed (${marker}):\n${output.slice(-3000)}`);
   log('PASS', marker);
}

const text = (page, id) => page.locator(id).innerText();
const waitText = (page, id, expected, timeout = 60000) => page.waitForFunction(([id, expected]) => {
   const node = document.querySelector(id);
   return node && (node.innerText || node.value || '').includes(expected);
}, [id, expected], {timeout});
const enabled = (page, id) => page.waitForFunction(id => {
   const node = document.querySelector(id);
   return node && !node.disabled;
}, id, {timeout: 60000});
const expect = (condition, message) => { if (!condition) throw new Error(message); };

(async () => {
   const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
   let page;
   for (let i = 0; i < 120 && !page; i++)
   {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(resolve => setTimeout(resolve, 1000));
   }
   if (!page) throw new Error('RStudio window did not load');
   // the first load sets the LOCALE cookie from the preference and reloads
   await page.waitForFunction(() => window.rstudio?.ready && document.cookie.includes('LOCALE=es'), null,
                              {timeout: 180000});
   await page.evaluate(() => window.rstudio.errors.clear());
   const body = await page.evaluate(() => document.body.innerText);
   expect(body.includes('Environment') && body.includes('Console'), 'upstream interface not in its compiled language');
   log('PASS ui_language "es" accepted (LOCALE cookie es); upstream interface keeps its compiled English');

   await page.evaluate(() => window.rstudio.commands.activateEnvironment());
   await page.locator('#rstudio_superrstudio_lfq').waitFor({state: 'visible', timeout: 60000});
   expect((await text(page, '#rstudio_superrstudio_scatter')).includes(sc.toolbarLabel), 'scatter toolbar label');
   expect((await text(page, '#rstudio_superrstudio_lfq')).includes(lf.toolbarLabel), 'LFQ toolbar label');
   log('PASS toolbar:', sc.toolbarLabel, '/', lf.toolbarLabel);

   await check(page,
      `peces <- data.frame(talla = c(10.5, 12.25, 14, 15.5, 17.25, 19), peso = c(1.5, 2.25, 3, 3.6, 4.9, 5.2)); ` +
      `data('synLFQ7', package = 'TropFishR'); srs_cells <- which(synLFQ7$catch > 0, arr.ind = TRUE); ` +
      `tallas <- data.frame(talla_mm = rep(synLFQ7$midLengths[srs_cells[, 1]] * 10, synLFQ7$catch[srs_cells]), ` +
      `fecha = format(rep(synLFQ7$dates[srs_cells[, 2]], synLFQ7$catch[srs_cells]), '%d/%m/%Y'), especie = 'Synthetic'); ` +
      `invisible(grDevices::graphics.off())`,
      'ES_SETUP_OK');

   // plot editor in Spanish; the generated R code and numbers are not localized
   await page.locator('#rstudio_superrstudio_scatter').click();
   await page.getByRole('dialog').waitFor();
   expect((await page.getByRole('dialog').innerText()).includes(sc.title), 'plot editor title');
   await page.waitForFunction(() => [...(document.getElementById('superrstudio_dataset')?.options || [])].some(o => o.value === 'peces'));
   await page.selectOption('#superrstudio_dataset', 'peces');
   await waitText(page, '#superrstudio_status', sc.ready);
   await page.selectOption('#superrstudio_x', 'talla');
   await page.selectOption('#superrstudio_y', 'peso');
   await page.selectOption('#superrstudio_fit', 'lm');
   await page.locator('#rstudio_superrstudio_preview').click();
   await waitText(page, '#superrstudio_status', sc.plotted);
   await waitText(page, '#superrstudio_model', 'ajustado');
   const model = await text(page, '#superrstudio_model');
   const code = await page.locator('#superrstudio_code').inputValue();
   log('model:\n' + model);
   expect(/R² = 0\.\d+/.test(model) && !/\d,\d/.test(model), 'model numbers must use a decimal point: ' + model);
   expect(code.includes('ggplot2::ggplot(peces, ') && code.includes('method = "lm"') && !/ajustado|Gráfico|talla de/.test(code),
          'generated R code changed: ' + code);
   await check(page, `srs_p <- eval(parse(text = ${JSON.stringify(code)})[[1]]); stopifnot(inherits(srs_p, 'ggplot'))`,
               'ES_PLOT_CODE_RUNS');
   const mojibake = /Ã|Â|â€|�/;
   expect(!mojibake.test(await page.getByRole('dialog').innerText()), 'broken accented characters in the plot editor');
   await shot(page, '1-plot-editor');
   await page.getByRole('dialog').getByRole('button', {name: sc.close}).click();
   await page.getByRole('dialog').waitFor({state: 'detached'});
   log('PASS plot editor in Spanish; model numbers with decimal point; R code unchanged and runs');

   // length-frequency window in Spanish
   await page.locator('#rstudio_superrstudio_lfq').click();
   await waitText(page, '#superrstudio_lfq_status', 'TropFishR 1.6.6');
   for (const key of ['tabData', 'tabClasses', 'tabGrowth', 'tabCompare', 'tabMortality', 'tabSaved'])
      expect((await page.locator('#superrstudio_lfq_tab_' + {tabData: 'data', tabClasses: 'classes',
         tabGrowth: 'growth', tabCompare: 'compare', tabMortality: 'mortality', tabSaved: 'saved'}[key]).innerText()) === lf[key],
             'tab ' + key);
   expect((await page.getByRole('dialog').innerText()).includes(lf.title), 'LFQ title');
   await page.waitForFunction(() => [...document.getElementById('superrstudio_lfq_dataset').options].some(o => o.value === 'tallas'));
   await page.selectOption('#superrstudio_lfq_dataset', 'tallas');
   await page.waitForFunction(() => [...document.getElementById('superrstudio_lfq_length').options].some(o => o.value === 'talla_mm'));
   await page.selectOption('#superrstudio_lfq_length', 'talla_mm');
   await page.selectOption('#superrstudio_lfq_unit', 'mm');
   await page.selectOption('#superrstudio_lfq_date', 'fecha');
   await page.selectOption('#superrstudio_lfq_date_format', '%d/%m/%Y');
   await page.locator('#rstudio_superrstudio_lfq_check').click();
   await waitText(page, '#superrstudio_lfq_report', lf.perDate);
   const usable = lf.checkSummary.split('{1}')[1].split('(')[0].trim();
   expect((await text(page, '#superrstudio_lfq_report')).includes(`27871 ${usable} (27871`), 'check summary in Spanish');
   await page.locator('#superrstudio_lfq_tab_classes').click();
   await page.fill('#superrstudio_lfq_bin_size', '2');
   await page.fill('#superrstudio_lfq_lmin', '7');
   await page.selectOption('#superrstudio_lfq_ma', '7');
   await page.locator('#rstudio_superrstudio_lfq_create').click();
   await waitText(page, '#superrstudio_lfq_created', lf.transformations);
   const created = await text(page, '#superrstudio_lfq_created');
   expect(created.startsWith(fill(lf.created, '8', '65', '27871', '', '').split(';')[0]), 'created text: ' + created);
   const lfqCode = await page.locator('#superrstudio_lfq_code').inputValue();
   expect(lfqCode.includes('TropFishR::lfqCreate(lfq_input') && lfqCode.includes('bin_size = 2'), 'LFQ code: ' + lfqCode);
   log('PASS data check and length classes in Spanish; code unchanged');

   // mortality: results and diagnostics come back as codes and are shown in Spanish
   await page.locator('#superrstudio_lfq_tab_mortality').click();
   await page.fill('#superrstudio_lfq_cc_linf', '123');
   await page.fill('#superrstudio_lfq_cc_k', '0.2');
   await page.selectOption('#superrstudio_lfq_m_method', 'then_growth');
   await enabled(page, '#rstudio_superrstudio_lfq_compute_z');
   await page.locator('#rstudio_superrstudio_lfq_compute_z').click();
   await waitText(page, '#superrstudio_lfq_mortality', lf.diagnostics);
   const mortality = await text(page, '#superrstudio_lfq_mortality');
   log('mortality:\n' + mortality);
   const first = await page.locator('#superrstudio_lfq_cc_first').inputValue();
   const last = await page.locator('#superrstudio_lfq_cc_last').inputValue();
   expect(/^Z = \d+\.\d+ por año/.test(mortality), 'Z line in Spanish with a decimal point');
   expect(mortality.includes(fill(lf.dAutomatic, first, last)), 'automatic-points diagnostic in Spanish');
   expect((await text(page, '#superrstudio_lfq_cc_points')).includes(lf.colLength), 'points table header');
   expect(!mojibake.test(await page.getByRole('dialog').innerText()), 'broken accented characters in the LFQ window');
   await shot(page, '2-mortality');
   log('PASS mortality results, diagnostics and table in Spanish');

   // saved analyses: restore warnings are shown in Spanish
   const library = path.join(evidence, 'es-analyses.json').replaceAll('\\', '/');
   fs.rmSync(library, {force: true});
   await page.locator('#superrstudio_lfq_tab_saved').click();
   await page.fill('#superrstudio_lfq_lib_path', library);
   await page.locator('#rstudio_superrstudio_lfq_lib_save_as').click();
   await waitText(page, '#superrstudio_lfq_lib_file', fill(lf.savedFile, ''));
   await page.fill('#superrstudio_lfq_lib_name', 'Análisis de prueba');
   await page.locator('#rstudio_superrstudio_lfq_lib_add').click();
   await page.waitForFunction(() => document.getElementById('superrstudio_lfq_lib_list').options.length === 1);
   await check(page, `srs_hidden <- tallas; rm(tallas)`, 'ES_DATASET_REMOVED');
   await page.locator('#rstudio_superrstudio_lfq_lib_restore').click();
   await waitText(page, '#superrstudio_lfq_lib_status', fill(lf.wDatasetMissing, 'tallas'));
   await check(page, `tallas <- srs_hidden; srs_lib <- readLines(${JSON.stringify(library)}, encoding = 'UTF-8'); ` +
               `stopifnot(any(grepl('"name": "An\\u00e1lisis de prueba"', srs_lib, fixed = TRUE)))`,
               'ES_ACCENTED_NAME_IN_FILE');
   await shot(page, '3-saved');
   log('PASS restore warning in Spanish; accented analysis name written to the file as UTF-8');

   const shown = await page.evaluate(() => document.body.innerText);
   expect(!mojibake.test(shown), 'broken accented characters on screen');
   await page.locator('#rstudio_superrstudio_lfq_close').click();
   const errors = await page.evaluate(() => window.rstudio.errors.list());
   if (errors.length) throw new Error('client exceptions: ' + JSON.stringify(errors));
   log('PASS no mojibake and no client exceptions');
   log('DESKTOP_ES_PASS');
   await browser.close();
})().catch(async error => {
   console.error(error);
   process.exitCode = 1;
   try
   {
      const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
      const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      console.error('cookie:', await page.evaluate(() => document.cookie));
      console.error('errors:', JSON.stringify(await page.evaluate(() => window.rstudio?.errors.list())));
      await shot(page, 'failure');
   }
   catch (e) { console.error('no diagnostics:', e.message); }
})
   .finally(() => process.exit());
