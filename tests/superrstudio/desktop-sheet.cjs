// Live desktop acceptance test for the data table window.
// SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario sheet (desktop
// with -Experimental -Automation and the isolated library, which has ggplot2,
// TropFishR and readxl). Pastes cells as a spreadsheet does, types a row with
// the keyboard, creates the data frame through the console, opens it in the
// plot editor and the length-frequency window, replaces it after the
// confirmation, reads a semicolon/decimal-comma Latin-1 CSV and an Excel
// sheet from typed paths, and edits a copy of a session data frame. Every
// result is compared in R in the console.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const project = path.resolve(__dirname, '../..').replaceAll('\\', '/');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
fs.mkdirSync(evidence, {recursive: true});
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const log = (...args) => console.log(...args);
const shot = (page, name) => page.screenshot({path: path.join(evidence, `sheet-${name}.png`)});

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
   // a line may keep spaces from a progress bar (readxl) after the marker
   if (!new RegExp(marker + '[ \\t]*\\n').test(output))
      throw new Error(`R check failed (${marker}):\n${output.slice(-3000)}`);
   log('PASS', marker);
}

// text printed by the console after a marker (one line)
async function printed(page, code, marker)
{
   await run(page, `cat('${marker}', ${code}, '\\n')`);
   const text = await page.locator('#rstudio_workbench_panel_console').innerText();
   const match = [...text.matchAll(new RegExp(marker + ' (.*)', 'g'))].pop();
   if (!match) throw new Error('nothing printed for ' + marker);
   return match[1].trim();
}

const waitText = (page, id, pattern, timeout = 60000) => page.waitForFunction(([id, source]) => {
   const node = document.querySelector(id);
   return node && new RegExp(source).test(node.innerText);
}, [id, pattern.source], {timeout});
const enabled = (page, id) => page.waitForFunction(id => {
   const node = document.querySelector(id);
   return node && !node.disabled;
}, id, {timeout: 60000});

// a paste event like the one a spreadsheet produces (tab-separated lines)
const paste = (page, id, text) => page.evaluate(([id, text]) => {
   const data = new DataTransfer();
   data.setData('text/plain', text);
   const target = document.getElementById(id);
   target.focus();
   target.dispatchEvent(new ClipboardEvent('paste', {clipboardData: data, bubbles: true, cancelable: true}));
}, [id, text]);

async function create(page, name, confirm = false)
{
   await page.fill('#superrstudio_sheet_name', name);
   await enabled(page, '#rstudio_superrstudio_sheet_create');
   await page.locator('#rstudio_superrstudio_sheet_create').click();
   if (confirm)
   {
      // replacing an object is confirmed in the window
      await waitText(page, '#superrstudio_sheet_status', new RegExp(`^An object named ${name} already exists`));
      await page.locator('#rstudio_superrstudio_sheet_replace').click();
   }
   await waitText(page, '#superrstudio_sheet_status', new RegExp(`^${name} is ready in the session`), 120000);
}

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

   // open the window from the Environment pane
   await page.evaluate(() => window.rstudio.commands.activateEnvironment());
   await page.locator('#rstudio_superrstudio_sheet').click();
   await page.waitForSelector('#superrstudio_sheet_grid #superrstudio_sheet_cell_10_3');

   // cells pasted into the first column name: names from the first line;
   // a fourth row typed with the keyboard (Tab to the right)
   await paste(page, 'superrstudio_sheet_col_1', 'talla\tpeso\tsexo\n12,5\t20\tH\n15\t41\tM\n18\t70,25\tH\n');
   if (await page.inputValue('#superrstudio_sheet_col_3') !== 'sexo' ||
       await page.inputValue('#superrstudio_sheet_cell_3_2') !== '70,25')
      throw new Error('pasted cells not in the table');
   await page.locator('#superrstudio_sheet_cell_4_1').click();
   await page.keyboard.type('21');
   await page.keyboard.press('Tab');
   await page.keyboard.type('115');
   await page.keyboard.press('Tab');
   await page.keyboard.type('M');
   await page.keyboard.press('Enter');
   log('PASS pasted cells (names from the first line) and a typed row');

   await page.locator('#rstudio_superrstudio_sheet_check').click();
   await waitText(page, '#superrstudio_sheet_status', /^4 rows and 3 columns: talla \(number\), peso \(number\), sexo \(text\)\.$/);
   if (!(await page.inputValue('#superrstudio_sheet_code')).startsWith('datos <- data.frame(\n   talla = c(12.5, 15, 18, 21)'))
      throw new Error('unexpected code: ' + await page.inputValue('#superrstudio_sheet_code'));
   await shot(page, '1-table');

   await run(page, `rm(list = intersect(c('srs_tabla', 'srs_csv', 'srs_excel', 'srs_tabla_2'), ls()))`);
   await create(page, 'srs_tabla');
   await check(page, `stopifnot(identical(srs_tabla, data.frame(talla = c(12.5, 15, 18, 21), ` +
      `peso = c(20, 41, 70.25, 115), sexo = c('H', 'M', 'H', 'M'))))`, 'SHEET_TYPED_OK');
   if (!(await page.locator('#rstudio_workbench_panel_console').innerText()).includes('srs_tabla <- data.frame('))
      throw new Error('the code did not run visibly in the console');
   log('PASS created through visible console code');

   // straight to the plot editor and the length-frequency window
   await enabled(page, '#rstudio_superrstudio_sheet_plot');
   await page.locator('#rstudio_superrstudio_sheet_plot').click();
   await page.waitForFunction(() => document.getElementById('superrstudio_dataset')?.value === 'srs_tabla', null, {timeout: 60000});
   await shot(page, '2-plot-editor');
   await page.locator('#rstudio_superrstudio_close').click();
   await page.locator('#rstudio_superrstudio_sheet_lfq').click();
   await page.waitForFunction(() => document.getElementById('superrstudio_lfq_dataset')?.value === 'srs_tabla', null, {timeout: 60000});
   await page.locator('#rstudio_superrstudio_lfq_close').click();
   log('PASS opened with the new data frame selected (plot editor, length frequency)');

   // replacing an existing object asks first
   await page.fill('#superrstudio_sheet_cell_1_1', '13');
   await create(page, 'srs_tabla', true);
   await check(page, `stopifnot(identical(srs_tabla$talla, c(13, 15, 18, 21)))`, 'SHEET_REPLACED_OK');

   // a CSV written in Latin-1 with semicolons and decimal commas, path typed
   const csv = await printed(page, `{ srs_f <- normalizePath(file.path(tempdir(), 'capturas.csv'), winslash = '/', mustWork = FALSE); ` +
      `writeBin(iconv('talla;especie\\n12,5;Merluza\\n13,25;Sard\\u00edna\\n', 'UTF-8', 'latin1', toRaw = TRUE)[[1]], srs_f); srs_f }`,
      'SHEET_CSV_PATH');
   await page.fill('#superrstudio_sheet_path', csv);
   await page.locator('#superrstudio_sheet_path').press('Enter');
   await waitText(page, '#superrstudio_sheet_file_info',
      /capturas\.csv: 2 rows and 2 columns[\s\S]*separator Semicolon, decimal mark Comma \(12,5\), encoding Latin-1 \(Windows\)/);
   if (await page.inputValue('#superrstudio_sheet_name') !== 'capturas')
      throw new Error('name not proposed from the file name');
   await shot(page, '3-csv');
   await create(page, 'srs_csv');
   await check(page, `stopifnot(identical(srs_csv, data.frame(talla = c(12.5, 13.25), especie = c('Merluza', 'Sard\\u00edna'))))`,
      'SHEET_CSV_OK');

   // an Excel workbook: sheets listed, another sheet chosen
   const book = await printed(page, `readxl::readxl_example('datasets.xlsx')`, 'SHEET_XLSX_PATH');
   await page.fill('#superrstudio_sheet_path', book);
   await page.locator('#superrstudio_sheet_path').press('Enter');
   await waitText(page, '#superrstudio_sheet_file_info', /datasets\.xlsx: \d+ rows/);
   await page.selectOption('#superrstudio_sheet_excel_sheet', 'chickwts');
   await page.locator('#rstudio_superrstudio_sheet_reread').click();
   await waitText(page, '#superrstudio_sheet_file_info', /datasets\.xlsx: 71 rows and 2 columns/);
   await create(page, 'srs_excel');
   await check(page, `stopifnot(identical(srs_excel, as.data.frame(readxl::read_excel(readxl::readxl_example('datasets.xlsx'), sheet = 'chickwts'))))`,
      'SHEET_EXCEL_OK');

   // a copy of a session data frame, edited and created under a new name
   await page.locator('#rstudio_superrstudio_sheet_new').click();
   await page.waitForFunction(() => [...document.getElementById('superrstudio_sheet_frames').options].some(o => o.value === 'srs_tabla'));
   await page.selectOption('#superrstudio_sheet_frames', 'srs_tabla');
   await page.locator('#rstudio_superrstudio_sheet_copy').click();
   await waitText(page, '#superrstudio_sheet_status', /^Copied srs_tabla \(4 rows\)/);
   if (await page.inputValue('#superrstudio_sheet_name') !== 'srs_tabla_2')
      throw new Error('copy name not proposed');
   await page.fill('#superrstudio_sheet_cell_2_3', 'H');
   await create(page, 'srs_tabla_2');
   await check(page, `stopifnot(identical(srs_tabla_2$sexo, c('H', 'H', 'H', 'M')), identical(srs_tabla$sexo, c('H', 'M', 'H', 'M')))`,
      'SHEET_COPY_OK');
   await shot(page, '4-copy');

   // a value that is not a number in a Number column is reported, nothing runs
   await page.selectOption('#superrstudio_sheet_type_1', 'number');
   await page.fill('#superrstudio_sheet_cell_2_1', 'doce');
   await page.locator('#rstudio_superrstudio_sheet_check').click();
   await waitText(page, '#superrstudio_sheet_status', /Column 'talla', row 2: 'doce' is not a number\./);
   log('PASS invalid value reported');

   await page.locator('#rstudio_superrstudio_sheet_close').click();
   await run(page, `rm(srs_tabla, srs_csv, srs_excel, srs_tabla_2, srs_f)`);
   const errors = await page.evaluate(() => window.rstudio.errors.list());
   if (errors.length) throw new Error('client exceptions: ' + JSON.stringify(errors));
   log('PASS no client exceptions');
   log('DESKTOP_SHEET_PASS');
   await browser.close();
})().catch(async error => {
   console.error(error);
   process.exitCode = 1;
   try
   {
      const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
      const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      console.error('status:', await page.evaluate(() => document.getElementById('superrstudio_sheet_status')?.innerText));
      console.error('errors:', JSON.stringify(await page.evaluate(() => window.rstudio.errors.list())));
      await shot(page, 'failure');
   }
   catch (e) { console.error('no diagnostics:', e.message); }
})
   .finally(() => process.exit());
