// Live desktop acceptance test for the length-frequency (TropFishR) workflow.
// SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario lfq (desktop with
// -Experimental -Automation and the isolated library holding TropFishR).
// Uses TropFishR's synLFQ7 reference data expanded into individual "tallas"
// with text dates, two species and invalid rows, and checks the dialog's
// numbers against R computed independently in the console.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const project = path.resolve(__dirname, '../..').replaceAll('\\', '/');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
fs.mkdirSync(evidence, {recursive: true});
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const log = (...args) => console.log(...args);
const shot = (page, name) => page.screenshot({path: path.join(evidence, `lfq-${name}.png`)});

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

// a number printed by the console after a marker
async function value(page, code, marker)
{
   await run(page, `cat('${marker}', ${code}, '\\n')`);
   const text = await page.locator('#rstudio_workbench_panel_console').innerText();
   const match = [...text.matchAll(new RegExp(marker + ' ([-0-9.e]+)', 'g'))].pop();
   if (!match) throw new Error('no value for ' + marker);
   return Number(match[1]);
}

const text = (page, id) => page.locator(id).innerText();
const waitText = (page, id, pattern, timeout = 60000) => page.waitForFunction(([id, source]) => {
   const node = document.querySelector(id);
   return node && new RegExp(source).test(node.innerText);
}, [id, pattern.source], {timeout});
const enabled = (page, id) => page.waitForFunction(id => {
   const node = document.querySelector(id);
   return node && !node.disabled;
}, id, {timeout: 60000});

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
   await page.evaluate(() => window.rstudio.errors.clear());

   await check(page,
      `data('synLFQ7', package = 'TropFishR'); srs_cells <- which(synLFQ7$catch > 0, arr.ind = TRUE); ` +
      `tallas <- data.frame(talla_mm = rep(synLFQ7$midLengths[srs_cells[, 1]] * 10, synLFQ7$catch[srs_cells]), ` +
      `fecha = format(rep(synLFQ7$dates[srs_cells[, 2]], synLFQ7$catch[srs_cells]), '%d/%m/%Y'), especie = 'Synthetic'); ` +
      `tallas <- rbind(tallas, data.frame(talla_mm = c(NA, 0, 250), fecha = c('01/01/2016', '01/01/2016', '31/02/2016'), ` +
      `especie = c('Synthetic', 'Synthetic', 'Synthetic')), data.frame(talla_mm = 300, fecha = '01/01/2016', especie = 'Otra')); ` +
      `tallas_original <- tallas; invisible(grDevices::graphics.off())`,
      'LFQ_SETUP_OK');
   const individuals = await value(page, 'sum(synLFQ7$catch)', 'SRS_TOTAL');

   await page.evaluate(() => window.rstudio.commands.activateEnvironment());
   await page.locator('#rstudio_superrstudio_lfq').click();
   await page.locator('#superrstudio_lfq_status').waitFor();
   await waitText(page, '#superrstudio_lfq_status', /TropFishR 1\.6\.6/);
   await page.waitForFunction(() => document.getElementById('superrstudio_lfq_dataset')?.options.length > 0);
   await enabled(page, '#rstudio_superrstudio_lfq_check');

   // 1. data mapping and checks
   await page.selectOption('#superrstudio_lfq_dataset', 'tallas');
   await page.waitForFunction(() => [...document.getElementById('superrstudio_lfq_length').options].some(o => o.value === 'talla_mm'));
   await page.selectOption('#superrstudio_lfq_length', 'talla_mm');
   await page.selectOption('#superrstudio_lfq_unit', 'mm');
   await page.selectOption('#superrstudio_lfq_date', 'fecha');
   await page.selectOption('#superrstudio_lfq_date_format', '%d/%m/%Y');
   await page.selectOption('#superrstudio_lfq_species_column', 'especie');
   await page.locator('#rstudio_superrstudio_lfq_check').click();
   await page.waitForFunction(() => [...document.getElementById('superrstudio_lfq_species').options].some(o => o.value === 'Synthetic'));
   await page.selectOption('#superrstudio_lfq_species', 'Synthetic');
   await page.locator('#rstudio_superrstudio_lfq_check').click();
   await waitText(page, '#superrstudio_lfq_report', /with other species/);
   const report = await text(page, '#superrstudio_lfq_report');
   log('report:\n' + report);
   for (const expected of [`${individuals} usable observations`, 'Removed: 1 row(s) with other species',
                           'Removed: 1 row(s) with missing or non-numeric length',
                           'Removed: 1 row(s) with length zero or negative',
                           'Removed: 1 row(s) with missing date or not in format %d/%m/%Y',
                           '2016-01-01:'])
      if (!report.includes(expected)) throw new Error('report lacks ' + expected);
   await shot(page, '1-data');
   log('PASS data check: removed rows per rule, invalid text date, other species, sample sizes per date');

   // 2. length classes
   await page.locator('#superrstudio_lfq_tab_classes').click();
   await page.fill('#superrstudio_lfq_bin_size', '2');
   await page.fill('#superrstudio_lfq_lmin', '7');
   await page.selectOption('#superrstudio_lfq_ma', '7');
   await page.locator('#rstudio_superrstudio_lfq_create').click();
   await waitText(page, '#superrstudio_lfq_created', /sampling dates/);
   const created = await text(page, '#superrstudio_lfq_created');
   if (!/^8 sampling dates, 65 length classes/.test(created)) throw new Error('created: ' + created);
   for (const id of ['#superrstudio_lfq_raw_image', '#superrstudio_lfq_restructured_image'])
      if (!(await page.locator(id).isVisible())) throw new Error(id + ' not shown');
   const code = await page.locator('#superrstudio_lfq_code').inputValue();
   if (!code.includes('TropFishR::lfqCreate(lfq_input') || !code.includes('TropFishR::lfqRestructure(lfq, MA = 7'))
      throw new Error('preparation code: ' + code);
   await shot(page, '2-classes');
   const asp = Number(/ASP\) ([0-9.e+-]+)/.exec(created)[1]);
   await check(page,
      `srs_env <- new.env(); eval(parse(text = ${JSON.stringify(code)}), envir = srs_env); ` +
      `srs_ref <- TropFishR::lfqRestructure(synLFQ7, MA = 7); ` +
      `stopifnot(identical(unname(srs_env$lfq$catch[1:64, ]) + 0, unname(synLFQ7$catch) + 0), ` +
      `isTRUE(all.equal(${asp}, signif(srs_env$lfq$ASP, 4))), identical(tallas, tallas_original))`,
      'LFQ_CODE_REPRODUCES_REFERENCE');
   log('PASS LFQ created and restructured; code reproduces synLFQ7 counts and the shown ASP');

   // 3. ELEFAN_GA with two seeds in a separate process; the console stays usable
   await page.locator('#superrstudio_lfq_tab_growth').click();
   await page.fill('#superrstudio_lfq_linf_min', '100');
   await page.fill('#superrstudio_lfq_linf_max', '140');
   await page.fill('#superrstudio_lfq_seeds', '1-2');
   await page.fill('#superrstudio_lfq_pop_size', '20');
   await page.fill('#superrstudio_lfq_max_iter', '8');
   await page.fill('#superrstudio_lfq_run', '8');
   await page.fill('#superrstudio_lfq_label', 'quick GA');
   await page.locator('#rstudio_superrstudio_lfq_start').click();
   await waitText(page, '#superrstudio_lfq_progress', /Analysis finished/, 180000);
   await waitText(page, '#superrstudio_lfq_groups', /ELEFAN_GA, 2 run\(s\)/);
   const groups = await text(page, '#superrstudio_lfq_groups');
   const linf = Number(/Linf mean ([0-9.e+-]+)/.exec(groups)[1]);
   await shot(page, '3-compare');
   log('compare:\n' + groups);

   // the recorded code of each run reproduces its estimate in the console
   await page.selectOption('#superrstudio_lfq_run_select', 'run1');
   await page.locator('#rstudio_superrstudio_lfq_show_fit').click();
   await page.locator('#superrstudio_lfq_fit_image').waitFor({state: 'visible'});
   const run1 = await page.locator('#superrstudio_lfq_code').inputValue();
   await page.selectOption('#superrstudio_lfq_run_select', 'run2');
   const run2 = await page.locator('#superrstudio_lfq_code').inputValue();
   await check(page,
      `srs_fit <- function(code) { e <- new.env(); invisible(capture.output(eval(parse(text = code), envir = e))); e$fit$par$Linf }; ` +
      `srs_l1 <- srs_fit(${JSON.stringify(run1)}); srs_l2 <- srs_fit(${JSON.stringify(run2)}); ` +
      `stopifnot(isTRUE(all.equal(${linf}, signif(mean(c(srs_l1, srs_l2)), 4))), identical(tallas, tallas_original))`,
      'LFQ_RUN_CODE_REPRODUCES_ESTIMATES');
   await shot(page, '4-fit');
   log('PASS ELEFAN_GA seeds 1-2 run in the background; comparison mean equals the runs recomputed from their code');

   // a long run: progress is reported, the console stays responsive, cancel stops it
   await page.locator('#superrstudio_lfq_tab_growth').click();
   await page.fill('#superrstudio_lfq_seeds', '3');
   await page.fill('#superrstudio_lfq_pop_size', '200');
   await page.fill('#superrstudio_lfq_max_iter', '5000');
   await page.fill('#superrstudio_lfq_run', '5000');
   await page.locator('#rstudio_superrstudio_lfq_start').click();
   await waitText(page, '#superrstudio_lfq_progress', /Run 1 of 1/, 60000);
   await check(page, `srs_busy_check <- sum(1:10)`, 'CONSOLE_RESPONSIVE_DURING_ANALYSIS');
   await page.locator('#rstudio_superrstudio_lfq_cancel').click();
   await waitText(page, '#superrstudio_lfq_progress', /Analysis cancelled/);
   log('PASS long analysis: progress shown, console responsive, cancelled');

   await page.locator('#rstudio_superrstudio_lfq_close').click();
   const errors = await page.evaluate(() => window.rstudio.errors.list());
   if (errors.length) throw new Error('client exceptions: ' + JSON.stringify(errors));
   log('PASS no client exceptions');
   log('DESKTOP_LFQ_PASS');
   await browser.close();
})().catch(async error => {
   console.error(error);
   process.exitCode = 1;
   // diagnostics: what the window showed and any client exceptions
   try
   {
      const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
      const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      console.error('status:', await page.evaluate(() => document.getElementById('superrstudio_lfq_status')?.innerText));
      console.error('errors:', JSON.stringify(await page.evaluate(() => window.rstudio.errors.list())));
      await shot(page, 'failure');
   }
   catch (e) { console.error('no diagnostics:', e.message); }
})
   .finally(() => process.exit());
