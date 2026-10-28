// Live desktop acceptance test for the visual scatter workflow.
// SPDX-License-Identifier: AGPL-3.0-only
//
// Requires a desktop started by tools/superrstudio/dev-run.ps1 with
// -Experimental -Automation -DebugPort 19381, and the Playwright client
// (see docs/superrstudio/baseline/windows-gui-2026-10-28.md).
//
//   node tests/superrstudio/desktop-scatter.cjs [ggplot2|no-ggplot2|disabled] [evidence-dir]
//
// "ggplot2" (default) needs ggplot2 in the session library; "no-ggplot2"
// expects a session library without it and checks the error path;
// "disabled" expects a desktop started without -Experimental.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const mode = process.argv[2] || 'ggplot2';
const project = path.resolve(__dirname, '../..').replaceAll('\\', '/');
const evidence = path.resolve(process.argv[3] || path.join(project, '.cache/superrstudio/gui-scatter'));
fs.mkdirSync(evidence, {recursive: true});
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';

const log = (...args) => console.log(...args);
const shot = (page, name) => page.screenshot({path: path.join(evidence, `${mode}-${name}.png`)});

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

// Run R code that must print the given marker; fail with the console text otherwise.
async function check(page, code, marker)
{
   await run(page, `${code}; cat('${marker}\\n')`);
   const output = await page.locator('#rstudio_workbench_panel_console').innerText();
   if (!output.includes(marker + '\n'))
      throw new Error(`R check failed (${marker}):\n${output.slice(-3000)}`);
   log('PASS', marker);
}

async function openDialog(page)
{
   await page.evaluate(() => window.rstudio.commands.activateEnvironment());
   const button = page.locator('#rstudio_superrstudio_scatter');
   await button.waitFor({state: 'visible', timeout: 30000});
   await button.click();
   const dialog = page.getByRole('dialog');
   await dialog.waitFor();
   await page.waitForFunction(() => document.getElementById('superrstudio_dataset')?.options.length > 0);
   return dialog;
}

async function status(page)
{
   return (await page.locator('#superrstudio_status').innerText()).trim();
}

async function waitStatus(page, pattern)
{
   await page.waitForFunction(source => {
      const node = document.getElementById('superrstudio_status');
      const text = node ? node.innerText : '';
      return new RegExp(source).test(text);
   }, pattern.source, {timeout: 60000});
   return status(page);
}

async function selectDataset(page, name)
{
   await page.selectOption('#superrstudio_dataset', name);
   await waitStatus(page, /Select numeric columns|no supported numeric/);
}

async function closeDialog(page)
{
   await page.getByRole('dialog').getByRole('button', {name: 'Close'}).click();
   await page.getByRole('dialog').waitFor({state: 'detached'});
}

(async () => {
   const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
   // the debugging port opens before the IDE window has loaded its page
   let page;
   for (let i = 0; i < 120 && !page; i++)
   {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(resolve => setTimeout(resolve, 1000));
   }
   if (!page) throw new Error('RStudio window did not load');
   await page.waitForFunction(() => window.rstudio?.ready, null, {timeout: 120000});
   await page.evaluate(() => window.rstudio.errors.clear());
   if (mode === 'disabled')
   {
      // Without SUPER_RSTUDIO_EXPERIMENTAL=1 the IDE is unchanged: the button
      // keeps its slot but stays hidden once the status RPC has answered.
      await page.evaluate(() => window.rstudio.commands.activateEnvironment());
      const button = page.locator('#rstudio_superrstudio_scatter');
      await button.waitFor({state: 'attached'});
      await page.waitForTimeout(5000);
      if (await button.isVisible()) throw new Error('scatter button visible while the feature is disabled');
      await shot(page, '1-disabled');
      log('PASS feature disabled by default (button hidden)');
      log('DESKTOP_SCATTER_DISABLED_PASS');
      return;
   }
   const opened = await page.evaluate(() => window.rstudio.documents.active()?.path || '');
   if (/[\\/]main[\\/]index\.js$/.test(opened)) throw new Error('launcher opened the Electron main script as a document');

   // Real data: the committed CSV (spaces in names, integer/double/logical/NA columns).
   await check(page,
      `fish <- read.csv('${project}/tests/superrstudio/scientific.csv', check.names = FALSE); ` +
      `fish_original <- fish; labels_only <- data.frame(site = c('A', 'B')); ` +
      `dupes <- data.frame(a = 1:2, b = 3:4); names(dupes) <- c('a', 'a'); not_a_frame <- 1:3; ` +
      `growth <- data.frame(age = c(1, 2, 3, 4, 5, 6, 7, 8), size = c(10.2, 19.8, 30.5, 39.6, 50.4, 59.1, 70.6, 79.8), ` +
      `site = rep(c('north', 'south'), 4)); growth_original <- growth; ` +
      `invisible(grDevices::graphics.off()); ` +
      `stopifnot(${mode === 'ggplot2' ? '' : '!'}requireNamespace('ggplot2', quietly = TRUE))`,
      'SCATTER_SETUP_OK');

   let dialog = await openDialog(page);
   const datasets = await page.$$eval('#superrstudio_dataset option', o => o.map(x => x.value));
   log('datasets offered:', datasets);
   // Only plain data frames with unique, nonempty names are offered.
   for (const expected of ['fish', 'fish_original', 'labels_only'])
      if (!datasets.includes(expected)) throw new Error(`missing dataset ${expected}`);
   for (const rejected of ['dupes', 'not_a_frame'])
      if (datasets.includes(rejected)) throw new Error(`unsupported object offered: ${rejected}`);
   log('PASS dataset discovery (data frames only; duplicate-name frame excluded)');

   // Invalid selection: a frame with no numeric columns cannot be plotted.
   await selectDataset(page, 'labels_only');
   if ((await page.$$eval('#superrstudio_x option', o => o.length)) !== 0) throw new Error('labels_only offered columns');
   if (await page.locator('#rstudio_superrstudio_preview').isEnabled()) throw new Error('preview enabled without numeric columns');
   log('PASS no-numeric-column frame:', await status(page));

   await selectDataset(page, 'fish');
   const columns = await page.$$eval('#superrstudio_x option', o => o.map(x => x.value));
   log('numeric columns offered:', columns);
   if (JSON.stringify(columns) !== JSON.stringify(['sample', 'length cm', 'mass_g']))
      throw new Error('unexpected numeric columns ' + JSON.stringify(columns));
   log('PASS numeric column discovery (logical/character/date columns excluded)');
   await page.selectOption('#superrstudio_x', 'length cm');
   await page.selectOption('#superrstudio_y', 'mass_g');
   await shot(page, '1-dialog');

   // The Plots pane renders into an <img> inside an about:blank iframe.
   const plotImage = () => page.evaluate(() => {
      const frame = document.getElementById('rstudio_plot_image_frame');
      const image = frame?.contentDocument?.getElementById('img');
      return frame && frame.offsetParent !== null && image ? image.getAttribute('src') : null;
   });
   const imageBefore = await plotImage();
   await page.locator('#rstudio_superrstudio_preview').click();

   if (mode === 'no-ggplot2')
   {
      const message = await waitStatus(page, /^ggplot2 is required/);
      log('PASS missing ggplot2 reported:', message);
      await shot(page, '2-missing-ggplot2');
      await closeDialog(page);
      await check(page, `stopifnot(identical(fish, fish_original), is.null(grDevices::dev.list()))`, 'NO_GGPLOT2_UNCHANGED');
      // Dialog validation errors must not spill into the user's console.
      const console = await page.locator('#rstudio_workbench_panel_console').innerText();
      if (console.includes('ggplot2 is required')) throw new Error('validation error printed in the console');
      log('PASS console free of dialog validation errors');
   }
   else
   {
      await waitStatus(page, /Plot created/);
      const code = await page.locator('#superrstudio_code').inputValue();
      log('generated code:\n' + code);
      fs.writeFileSync(path.join(evidence, 'generated-scatter.R'), code);
      if (!/ggplot2::ggplot\(fish, ggplot2::aes\(x = \.data\[\["length cm"\]\], y = \.data\[\["mass_g"\]\]\)\)/.test(code))
         throw new Error('unexpected generated code');

      // The Plots pane must be activated and show a newly rendered plot.
      let src = null;
      for (let i = 0; i < 60 && (!src || src === imageBefore); i++)
      {
         await page.waitForTimeout(500);
         src = await plotImage();
      }
      if (!src || src === imageBefore || !/\/graphics\/.+\.png/.test(src))
         throw new Error('Plots pane not visible or no new plot: ' + src);
      log('PASS Plots pane visible with new plot:', src);
      await shot(page, '2-preview');

      // (Stale/deleted-data rejection is covered by tests/superrstudio/visual-scatter.R;
      // the modal dialog blocks console input, so it is not driven here.)
      await closeDialog(page);
      await check(page, `stopifnot(identical(fish, fish_original), !is.null(grDevices::dev.list()))`, 'PREVIEW_SOURCE_UNCHANGED');

      // Generated code reproduces the plot from the user's data in the console.
      await check(page,
         `srs_plot <- eval(parse(text = ${JSON.stringify(code)})); srs_built <- ggplot2::ggplot_build(srs_plot); ` +
         `stopifnot(identical(srs_built$data[[1]]$x, as.numeric(fish[['length cm']])), ` +
         `identical(srs_built$data[[1]]$y, as.numeric(fish$mass_g)), identical(fish, fish_original)); print(srs_plot)`,
         'GENERATED_CODE_REPRODUCES_PLOT');

      // Appearance: title, axis title, colour, size, opacity and theme, with undo.
      dialog = await openDialog(page);
      await selectDataset(page, 'fish');
      await page.selectOption('#superrstudio_x', 'length cm');
      await page.selectOption('#superrstudio_y', 'mass_g');
      if (await page.locator('#superrstudio_undo').isEnabled()) throw new Error('undo enabled before any change');
      const title = 'Fish "length" vs mass';
      await page.fill('#superrstudio_title', title);
      await page.locator('#superrstudio_title').press('Tab');            // commits the value
      await page.fill('#superrstudio_xlabel', 'Length (cm)');
      await page.locator('#superrstudio_xlabel').press('Tab');
      await page.selectOption('#superrstudio_colour', '#0072B2');
      await page.selectOption('#superrstudio_size', '3');
      await page.selectOption('#superrstudio_alpha', '0.6');
      await page.selectOption('#superrstudio_theme', 'classic');
      await page.selectOption('#superrstudio_theme', 'bw');
      await page.locator('#superrstudio_undo').click();                  // back to classic
      if (await page.inputValue('#superrstudio_theme') !== 'classic') throw new Error('undo did not restore the theme');
      log('PASS appearance undo restores the previous setting');
      const imageBeforeStyled = await plotImage();
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const styledCode = await page.locator('#superrstudio_code').inputValue();
      log('styled code:\n' + styledCode);
      fs.writeFileSync(path.join(evidence, 'generated-scatter-styled.R'), styledCode);
      for (const part of ['ggplot2::geom_point(colour = "#0072B2", size = 3, alpha = 0.6)',
                          'ggplot2::labs(title = "Fish \\"length\\" vs mass", x = "Length (cm)")',
                          'ggplot2::theme_classic()', 'SuperRStudio scatter v3'])
         if (!styledCode.includes(part)) throw new Error('styled code lacks ' + part);
      let styledSrc = null;
      for (let i = 0; i < 60 && (!styledSrc || styledSrc === imageBeforeStyled); i++)
      {
         await page.waitForTimeout(500);
         styledSrc = await plotImage();
      }
      if (!styledSrc || styledSrc === imageBeforeStyled) throw new Error('styled plot not rendered');
      await shot(page, '2b-styled-preview');
      await page.locator('#superrstudio_reset').click();
      if (await page.inputValue('#superrstudio_title') !== '' || await page.inputValue('#superrstudio_theme') !== 'grey')
         throw new Error('reset did not restore defaults');
      log('PASS styled preview rendered; reset restores defaults');
      await closeDialog(page);
      await check(page,
         `srs_plot <- eval(parse(text = ${JSON.stringify(styledCode)})); ` +
         `stopifnot(identical(srs_plot$labels$title, ${JSON.stringify(title)}), identical(srs_plot$labels$x, 'Length (cm)'), ` +
         `identical(srs_plot$layers[[1]]$aes_params$colour, '#0072B2'), isTRUE(all.equal(srs_plot$theme, ggplot2::theme_classic())), ` +
         `identical(fish, fish_original))`,
         'STYLED_CODE_REPRODUCES_APPEARANCE');

      // Lines with points plus a linear regression with a 90% band; the
      // statistics shown must equal summary(lm()) computed in the console.
      dialog = await openDialog(page);
      await selectDataset(page, 'growth');
      await page.selectOption('#superrstudio_x', 'age');
      await page.selectOption('#superrstudio_y', 'size');
      if (await page.locator('#superrstudio_line_order').isEnabled()) throw new Error('line order enabled for points');
      await page.selectOption('#superrstudio_geometry', 'lines_points');
      if (!(await page.locator('#superrstudio_line_order').isEnabled())) throw new Error('line order disabled for lines');
      const hint = await page.locator('#superrstudio_order_hint').innerText();
      if (!/increasing X/.test(hint)) throw new Error('order hint missing: ' + hint);
      await page.selectOption('#superrstudio_line_type', 'dashed');
      await page.selectOption('#superrstudio_fit', 'lm');
      await page.selectOption('#superrstudio_fit_level', '0.9');
      await page.selectOption('#superrstudio_fit_colour', '#D55E00');
      const imageBeforeFit = await plotImage();
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const fitCode = await page.locator('#superrstudio_code').inputValue();
      fs.writeFileSync(path.join(evidence, 'generated-scatter-fit.R'), fitCode);
      for (const part of ['ggplot2::geom_line(linetype = "dashed")', 'ggplot2::geom_point()',
                          'ggplot2::geom_smooth(method = "lm", formula = y ~ x, level = 0.9, colour = "#D55E00")',
                          'summary(stats::lm(y ~ x, data = data.frame(x = growth[["age"]], y = growth[["size"]])))'])
         if (!fitCode.includes(part)) throw new Error('fit code lacks ' + part);
      const modelText = await page.locator('#superrstudio_model').innerText();
      log('model summary:\n' + modelText);
      const r2 = /R² = ([0-9.e-]+)/.exec(modelText);
      if (!r2 || !/size = .+ \* age/.test(modelText) || !/Exploratory/.test(modelText))
         throw new Error('model summary incomplete: ' + modelText);
      let fitSrc = null;
      for (let i = 0; i < 60 && (!fitSrc || fitSrc === imageBeforeFit); i++)
      {
         await page.waitForTimeout(500);
         fitSrc = await plotImage();
      }
      if (!fitSrc || fitSrc === imageBeforeFit) throw new Error('fit plot not rendered');
      await shot(page, '2d-lines-fit');
      await page.selectOption('#superrstudio_fit', 'loess');
      if (!(await page.locator('#superrstudio_fit_span').isEnabled())) throw new Error('span disabled for loess');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const loessText = await page.locator('#superrstudio_model').innerText();
      if (!/LOESS span 0.75/.test(loessText) || /R² =/.test(loessText)) throw new Error('loess summary wrong: ' + loessText);
      log('PASS lines + lm fit (code, equation, R² shown) and loess summary');
      await closeDialog(page);
      await check(page,
         `srs_model <- summary(stats::lm(size ~ age, data = growth)); ` +
         `stopifnot(isTRUE(all.equal(${r2[1]}, signif(srs_model$r.squared, 4))), identical(growth, growth_original)); ` +
         `srs_plot <- eval(parse(text = ${JSON.stringify(fitCode.split('\n# Linear model')[0])})); ` +
         `srs_smooth <- ggplot2::ggplot_build(srs_plot)$data[[3]]; ` +
         `srs_ref <- stats::predict(stats::lm(size ~ age, data = growth), data.frame(age = srs_smooth$x), interval = 'confidence', level = 0.9); ` +
         `stopifnot(isTRUE(all.equal(srs_smooth$ymin, unname(srs_ref[, 'lwr']))))`,
         'FIT_MATCHES_REFERENCE_LM');

      // Histogram: one numeric variable, explicit bins, fill by a category.
      dialog = await openDialog(page);
      await selectDataset(page, 'growth');
      await page.selectOption('#superrstudio_kind', 'histogram');
      if (await page.locator('#superrstudio_y').isVisible()) throw new Error('Y shown for a histogram');
      if (!(await page.locator('#superrstudio_bins').isVisible())) throw new Error('bins hidden for a histogram');
      if (await page.locator('#superrstudio_fit').isVisible()) throw new Error('fit shown for a histogram');
      await page.selectOption('#superrstudio_x', 'size');
      await page.selectOption('#superrstudio_bins', '10');
      await page.selectOption('#superrstudio_colour_by', 'site');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const histCode = await page.locator('#superrstudio_code').inputValue();
      fs.writeFileSync(path.join(evidence, 'generated-histogram.R'), histCode);
      for (const part of ['SuperRStudio histogram v3', 'ggplot2::aes(x = .data[["size"]], fill = .data[["site"]])',
                          'ggplot2::geom_histogram(bins = 10)', 'ggplot2::scale_fill_viridis_d()'])
         if (!histCode.includes(part)) throw new Error('histogram code lacks ' + part);
      const histText = await page.locator('#superrstudio_model').innerText();
      if (!/n = 8 finite values \(0 non-finite removed\); 10 bins/.test(histText)) throw new Error('histogram summary: ' + histText);
      await page.waitForTimeout(1500);
      await shot(page, '2e-histogram');
      log('PASS histogram (variable, bins, fill column, summary)');

      // Boxplot: numeric response by a group, outliers hidden, observations overlaid.
      await page.selectOption('#superrstudio_kind', 'boxplot');
      if (!(await page.locator('#superrstudio_show_outliers').isVisible())) throw new Error('outlier option hidden');
      await page.selectOption('#superrstudio_x', 'site');
      await page.selectOption('#superrstudio_y', 'size');
      await page.selectOption('#superrstudio_colour_by', '');
      await page.locator('#superrstudio_show_points input').check();   // GWT CheckBox: id on the wrapper span
      await page.selectOption('#superrstudio_fill', '#56B4E9');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const boxCode = await page.locator('#superrstudio_code').inputValue();
      fs.writeFileSync(path.join(evidence, 'generated-boxplot.R'), boxCode);
      for (const part of ['SuperRStudio boxplot v3', 'ggplot2::aes(x = .data[["site"]], y = .data[["size"]])',
                          'ggplot2::geom_boxplot(fill = "#56B4E9")',
                          'ggplot2::geom_point(position = ggplot2::position_jitter(width = 0.15, height = 0, seed = 1))'])
         if (!boxCode.includes(part)) throw new Error('boxplot code lacks ' + part);
      const boxText = await page.locator('#superrstudio_model').innerText();
      log('box summary:\n' + boxText);
      const medians = [...boxText.matchAll(/^(north|south): n = 4; median ([0-9.e-]+)/gm)].map(m => [m[1], m[2]]);
      if (medians.length !== 2 || !/stats::quantile type 7/.test(boxText)) throw new Error('box summary: ' + boxText);
      await page.waitForTimeout(1500);
      await shot(page, '2f-boxplot');
      await closeDialog(page);
      await check(page,
         medians.map(([site, median]) =>
            `stopifnot(isTRUE(all.equal(${median}, signif(stats::quantile(growth$size[growth$site == '${site}'], 0.5, type = 7, names = FALSE), 4))))`).join('; ') +
         `; srs_box <- ggplot2::ggplot_build(eval(parse(text = ${JSON.stringify(boxCode)})))$data[[1]]; ` +
         `stopifnot(isTRUE(all.equal(srs_box$middle, as.vector(tapply(growth$size, growth$site, stats::median)))), identical(growth, growth_original))`,
         'BOXPLOT_MATCHES_REFERENCE');
      log('PASS boxplot (group, overlay, fill, statistics equal quantile type 7)');

      // Colour by a character column: fixed colour is disabled, viridis scale emitted.
      dialog = await openDialog(page);
      await selectDataset(page, 'fish');
      const colourColumns = await page.$$eval('#superrstudio_colour_by option', o => o.map(x => x.value));
      if (JSON.stringify(colourColumns) !== JSON.stringify(['', 'sample', 'site', 'length cm', 'mass_g', 'observed', 'date', 'note']))
         throw new Error('unexpected colour columns ' + JSON.stringify(colourColumns));
      await page.selectOption('#superrstudio_x', 'length cm');
      await page.selectOption('#superrstudio_y', 'mass_g');
      await page.selectOption('#superrstudio_colour', '#E69F00');
      await page.selectOption('#superrstudio_colour_by', 'site');
      if (await page.locator('#superrstudio_colour').isEnabled() || await page.inputValue('#superrstudio_colour') !== '')
         throw new Error('fixed colour not disabled/reset while colouring by column');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const mappedCode = await page.locator('#superrstudio_code').inputValue();
      fs.writeFileSync(path.join(evidence, 'generated-scatter-colour.R'), mappedCode);
      for (const part of ['colour = .data[["site"]]', 'ggplot2::scale_colour_viridis_d()', '"colour_by":"site"'])
         if (!mappedCode.includes(part)) throw new Error('mapped code lacks ' + part);
      await page.waitForTimeout(1500);
      await shot(page, '2c-colour-by');
      log('PASS colour by column (fixed colour disabled, discrete viridis scale)');
      await closeDialog(page);
      await check(page,
         `srs_built <- ggplot2::ggplot_build(eval(parse(text = ${JSON.stringify(mappedCode)}))); ` +
         `stopifnot(length(unique(srs_built$data[[1]]$colour)) == 2L, identical(fish, fish_original))`,
         'COLOUR_MAPPING_REPRODUCES');

      // Export opens the same code in a new, unsaved R script.
      dialog = await openDialog(page);
      await selectDataset(page, 'fish');
      await page.selectOption('#superrstudio_x', 'length cm');
      await page.selectOption('#superrstudio_y', 'mass_g');
      await page.locator('#rstudio_superrstudio_export').click();
      await page.getByRole('dialog').waitFor({state: 'detached'});
      await page.waitForFunction(() => window.rstudio.documents.activeEditor()?.getValue().includes('SuperRStudio scatter v3'));
      const script = await page.evaluate(() => window.rstudio.documents.activeEditor().getValue());
      if (script !== code) throw new Error('exported script differs from previewed code:\n' + script);
      log('PASS export opens identical code in a new R script');
      await shot(page, '3-exported-script');
      await page.evaluate(() => window.rstudio.documents.closeAllNoSave());
   }

   const errors = await page.evaluate(() => window.rstudio.errors.list());
   if (errors.length) throw new Error('client exceptions: ' + JSON.stringify(errors));
   log('PASS no client exceptions');
   log(`DESKTOP_SCATTER_${mode.toUpperCase().replace('-', '_')}_PASS`);
   await browser.close();
})().catch(error => { console.error(error); process.exitCode = 1; })
   // an open CDP connection keeps node alive after a failure
   .finally(() => process.exit());
