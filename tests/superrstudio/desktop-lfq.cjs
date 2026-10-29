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

   // the sampling period is a counted filter
   await page.fill('#superrstudio_lfq_period_start', '2016-03-01');
   await page.locator('#rstudio_superrstudio_lfq_check').click();
   await waitText(page, '#superrstudio_lfq_report', /sampled before 2016-03-01/);
   const before = await value(page, "sum(synLFQ7$catch[, synLFQ7$dates < as.Date('2016-03-01')])", 'SRS_BEFORE');
   if (!(await text(page, '#superrstudio_lfq_report')).includes(`Removed: ${before} row(s) with sampled before 2016-03-01`))
      throw new Error('period filter count');
   await page.fill('#superrstudio_lfq_period_start', '');
   log('PASS sampling period filter counted in the data check');

   // 2. length classes
   await page.locator('#superrstudio_lfq_tab_classes').click();
   await page.fill('#superrstudio_lfq_bin_size', '2');
   await page.fill('#superrstudio_lfq_lmin', '7');
   await page.selectOption('#superrstudio_lfq_ma', '7');
   await page.locator('#rstudio_superrstudio_lfq_create').click();
   await waitText(page, '#superrstudio_lfq_created', /sampling dates/);
   const created = await text(page, '#superrstudio_lfq_created');
   if (!/^8 sampling dates, 65 length classes/.test(created) || !created.includes('lfqRestructure: moving average over 7'))
      throw new Error('created: ' + created);
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

   // seasonal growth (C, ts) with ELEFAN_GA
   await page.locator('#superrstudio_lfq_seasonalised input').check();
   await page.fill('#superrstudio_lfq_seeds', '4');
   await page.fill('#superrstudio_lfq_pop_size', '20');
   await page.fill('#superrstudio_lfq_max_iter', '8');
   await page.fill('#superrstudio_lfq_run', '8');
   await page.fill('#superrstudio_lfq_label', 'seasonal');
   await enabled(page, '#rstudio_superrstudio_lfq_start');
   await page.locator('#rstudio_superrstudio_lfq_start').click();
   await waitText(page, '#superrstudio_lfq_progress', /Analysis finished/, 180000);
   await waitText(page, '#superrstudio_lfq_runs', /seasonal/);
   const seasonalRow = await page.evaluate(() => [...document.querySelectorAll('#superrstudio_lfq_runs tr')]
      .map(r => [...r.cells].map(c => c.innerText)).find(cells => cells[1] === 'seasonal'));
   const [cValue, tsValue] = [Number(seasonalRow[11]), Number(seasonalRow[12])];
   if (!(cValue >= 0 && cValue <= 1 && tsValue >= 0 && tsValue <= 1 && seasonalRow[11] !== ''))
      throw new Error('seasonal row: ' + seasonalRow);
   const varies = await text(page, '#superrstudio_lfq_varies');
   if (!varies.includes('search ranges') || !varies.includes('random seeds')) throw new Error('varies: ' + varies);
   await page.selectOption('#superrstudio_lfq_run_select', 'run3');
   const run3 = await page.locator('#superrstudio_lfq_code').inputValue();
   if (!run3.includes('seasonalised = TRUE') || !run3.includes('C = 0')) throw new Error('seasonal code: ' + run3);
   await check(page,
      `srs_e <- new.env(); invisible(capture.output(eval(parse(text = ${JSON.stringify(run3)}), envir = srs_e))); ` +
      `stopifnot(isTRUE(all.equal(${cValue}, signif(srs_e$fit$par$C, 4))), isTRUE(all.equal(${tsValue}, signif(srs_e$fit$par$ts, 4))))`,
      'LFQ_SEASONAL_CODE_REPRODUCES');
   await shot(page, '5-seasonal');
   log('PASS seasonal ELEFAN_GA: C and ts shown, reproduced from the code; comparison names search ranges and seeds');

   // 5. mortality: catch curve with growth parameters of run 1
   await page.locator('#superrstudio_lfq_tab_mortality').click();
   await page.selectOption('#superrstudio_lfq_cc_run', 'run1');
   await page.locator('#rstudio_superrstudio_lfq_cc_use_run').click();
   const ccLinf = await page.locator('#superrstudio_lfq_cc_linf').inputValue();
   if (!(Number(ccLinf) > 100) || (await page.locator('#superrstudio_lfq_cc_c').inputValue()) !== '')
      throw new Error('growth parameters not taken from run 1: ' + ccLinf);
   await page.selectOption('#superrstudio_lfq_m_method', 'then_growth');
   await page.locator('#rstudio_superrstudio_lfq_compute_z').click();
   await waitText(page, '#superrstudio_lfq_mortality', /Z = /);
   let mortality = await text(page, '#superrstudio_lfq_mortality');
   log('mortality:\n' + mortality);
   if (!mortality.includes("chosen by TropFishR's automatic rule") || !mortality.includes('M = ') ||
       !(await page.locator('#superrstudio_lfq_cc_image').isVisible()))
      throw new Error('mortality result: ' + mortality);
   const z = Number(/Z = ([0-9.e+-]+)/.exec(mortality)[1]);
   const e = Number(/E = F \/ Z = ([0-9.e+-]*[0-9])/.exec(mortality)[1]);
   const ccCode = await page.locator('#superrstudio_lfq_code').inputValue();
   await check(page,
      `srs_e <- new.env(); invisible(capture.output(suppressWarnings(eval(parse(text = ${JSON.stringify(ccCode)}), envir = srs_e)))); ` +
      `stopifnot(isTRUE(all.equal(${z}, signif(srs_e$cc$Z, 4))), isTRUE(all.equal(${e}, signif(srs_e$E, 4))), ` +
      `identical(tallas, tallas_original))`,
      'LFQ_CATCH_CURVE_CODE_REPRODUCES');
   const first = Number(await page.locator('#superrstudio_lfq_cc_first').inputValue());
   const pointRows = await page.locator('#superrstudio_lfq_cc_points tr').count();
   const used = await page.evaluate(() => [...document.querySelectorAll('#superrstudio_lfq_cc_points tr')]
      .filter(r => r.cells[4]?.innerText === 'yes').length);
   if (!(first > 1) || pointRows < 20 || !(used >= 3)) throw new Error(`points: first ${first}, rows ${pointRows}, used ${used}`);
   await page.fill('#superrstudio_lfq_cc_first', String(first + 2));
   await page.locator('#rstudio_superrstudio_lfq_compute_z').click();
   await waitText(page, '#superrstudio_lfq_mortality', new RegExp(`classes ${first + 2} to`));
   mortality = await text(page, '#superrstudio_lfq_mortality');
   if (mortality.includes('automatic rule')) throw new Error('chosen points still reported as automatic');
   await shot(page, '6-mortality');
   log('PASS catch curve: growth from run 1, automatic then chosen points, Z, M, E reproduced from the code');

   // 6. saved analyses written to a file
   const library = path.join(evidence, 'lfq-analyses.json').replaceAll('\\', '/');
   fs.rmSync(library, {force: true});
   await page.locator('#superrstudio_lfq_tab_saved').click();
   await page.fill('#superrstudio_lfq_lib_path', library);
   await page.locator('#rstudio_superrstudio_lfq_lib_save_as').click();
   await waitText(page, '#superrstudio_lfq_lib_file', /File: /);
   await page.selectOption('#superrstudio_lfq_lib_source', '');
   await page.fill('#superrstudio_lfq_lib_name', 'Current form');
   await page.locator('#rstudio_superrstudio_lfq_lib_add').click();
   await page.waitForFunction(() => document.getElementById('superrstudio_lfq_lib_list').options.length === 1);
   await page.selectOption('#superrstudio_lfq_lib_source', 'run1');
   await page.fill('#superrstudio_lfq_lib_name', 'Seed 1');
   await enabled(page, '#rstudio_superrstudio_lfq_lib_add');
   await page.locator('#rstudio_superrstudio_lfq_lib_add').click();
   await page.waitForFunction(() => document.getElementById('superrstudio_lfq_lib_list').options.length === 2);
   const items = await page.evaluate(() => [...document.getElementById('superrstudio_lfq_lib_list').options].map(o => o.text));
   if (!items[1].startsWith('Seed 1') || !items[1].includes('Linf ')) throw new Error('items: ' + items);
   // rename, duplicate and delete are written to the file
   await page.fill('#superrstudio_lfq_lib_name', 'Seed 1 (GA)');
   await page.locator('#rstudio_superrstudio_lfq_lib_rename').click();
   await waitText(page, '#superrstudio_lfq_lib_list', /Seed 1 \(GA\)/);
   await page.locator('#rstudio_superrstudio_lfq_lib_duplicate').click();
   await page.waitForFunction(() => document.getElementById('superrstudio_lfq_lib_list').options.length === 3);
   await page.selectOption('#superrstudio_lfq_lib_list', {index: 2});
   await enabled(page, '#rstudio_superrstudio_lfq_lib_delete');
   await page.locator('#rstudio_superrstudio_lfq_lib_delete').click();
   await page.waitForFunction(() => document.getElementById('superrstudio_lfq_lib_list').options.length === 2);
   await check(page,
      `srs_lib <- readLines(${JSON.stringify(library)}, encoding = 'UTF-8'); ` +
      `stopifnot(any(grepl('"format": "superrstudio-lfq-analyses"', srs_lib, fixed = TRUE)), ` +
      `sum(grepl('^      "name": ', srs_lib)) == 2L, any(grepl('"name": "Seed 1 (GA)"', srs_lib, fixed = TRUE)), ` +
      `any(grepl('"tropfishr": "1.6.6"', srs_lib, fixed = TRUE)))`,
      'LFQ_LIBRARY_FILE_WRITTEN');
   // compare the two saved analyses
   await page.selectOption('#superrstudio_lfq_lib_list', {index: 0});
   await page.selectOption('#superrstudio_lfq_lib_other', {index: 1});
   await enabled(page, '#rstudio_superrstudio_lfq_lib_compare');
   await page.locator('#rstudio_superrstudio_lfq_lib_compare').click();
   await waitText(page, '#superrstudio_lfq_lib_status', /Differences between "Current form" and "Seed 1 \(GA\)"/);
   const comparison = await text(page, '#superrstudio_lfq_lib_status');
   if (!comparison.includes('seeds: 4 → 1') || !comparison.includes('seasonalised: true → false'))
      throw new Error('comparison: ' + comparison);
   // restoring with changed data, and with the dataset missing, warns and substitutes nothing
   await page.selectOption('#superrstudio_lfq_lib_list', {index: 1});
   await check(page, `tallas <- rbind(tallas, tallas[1, ])`, 'LFQ_DATA_CHANGED');
   await page.locator('#rstudio_superrstudio_lfq_lib_restore').click();
   await waitText(page, '#superrstudio_lfq_lib_status', /differ from when the analysis was saved/);
   await check(page, `srs_hidden <- tallas_original; rm(tallas)`, 'LFQ_DATASET_REMOVED');
   await page.locator('#rstudio_superrstudio_lfq_lib_rerun').click();
   await waitText(page, '#superrstudio_lfq_lib_status', /does not exist in this session[\s\S]*Not run/);
   await check(page, `tallas <- srs_hidden; stopifnot(identical(tallas, tallas_original))`, 'LFQ_DATASET_BACK');
   // restoring a run's configuration fills the form; running it again reproduces the estimate
   await page.locator('#rstudio_superrstudio_lfq_lib_restore').click();
   await waitText(page, '#superrstudio_lfq_lib_status', /Settings of "Seed 1 \(GA\)" restored\.$/);
   if ((await page.locator('#superrstudio_lfq_seeds').inputValue()) !== '1' ||
       (await page.locator('#superrstudio_lfq_pop_size').inputValue()) !== '20' ||
       (await page.locator('#superrstudio_lfq_seasonalised input').isChecked()))
      throw new Error('settings not restored');
   await shot(page, '7-saved');
   const runCount = await page.locator('#superrstudio_lfq_runs tr').count();
   await page.locator('#rstudio_superrstudio_lfq_lib_rerun').click();
   await waitText(page, '#superrstudio_lfq_progress', /Analysis finished/, 180000);
   await page.waitForFunction(n => document.querySelectorAll('#superrstudio_lfq_runs tr').length > n, runCount);
   const linfs = await page.evaluate(() => [...document.querySelectorAll('#superrstudio_lfq_runs tr')].slice(1)
      .map(r => r.cells[8].innerText));
   if (linfs[linfs.length - 1] !== linfs[0]) throw new Error('re-run Linf differs: ' + linfs);
   log('PASS saved analyses: file written, rename/duplicate/delete, compare, warnings for changed and missing data, re-run reproduces run 1');

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
