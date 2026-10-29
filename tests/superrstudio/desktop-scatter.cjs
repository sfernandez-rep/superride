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
   await choose(page, '#superrstudio_dataset', name);
   await waitStatus(page, /Select columns|no supported numeric/);
}

// Settings are grouped in tabs; show the tab holding a control first.
async function reveal(page, selector)
{
   await page.evaluate(selector => {
      const page = document.querySelector(selector)?.closest('[data-superrstudio-tab]');
      const tab = page && document.getElementById('superrstudio_tab_' + page.getAttribute('data-superrstudio-tab'));
      if (tab && tab.getAttribute('aria-selected') !== 'true') tab.click();
   }, selector);
}

async function choose(page, selector, value)
{
   await reveal(page, selector);
   return page.selectOption(selector, value);
}

async function type(page, selector, value)
{
   await reveal(page, selector);
   return page.fill(selector, value);
}

async function waitCode(page, pattern)
{
   await page.waitForFunction(source => new RegExp(source).test(document.getElementById('superrstudio_code')?.value || ''),
                              pattern.source, {timeout: 60000});
   return page.locator('#superrstudio_code').inputValue();
}

// Element positions as the session computes them for the same code
// (fractions of the preview image), read back from the console.
async function plotMap(page, code, expression, marker)
{
   await run(page, `srs_map <- .rs.superrstudioInteractive(eval(parse(text = ${JSON.stringify(code)}))); ` +
                   `cat('${marker}', ${expression}, '\\n')`);
   const text = await page.locator('#rstudio_workbench_panel_console').innerText();
   const match = [...text.matchAll(new RegExp(marker + ' ([-0-9. e]+)', 'g'))].pop();
   if (!match) throw new Error('no element map in the console:\n' + text.slice(-2000));
   return match[1].trim().split(/\s+/).map(Number);
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
      `if (requireNamespace('tibble', quietly = TRUE)) fish_tbl <- tibble::as_tibble(fish); ` +
      `if (requireNamespace('data.table', quietly = TRUE)) fish_dt <- data.table::as.data.table(fish); ` +
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

   if (mode === 'ggplot2')
   {
      // tibbles and data.tables are offered, labelled with their kind
      const labels = await page.$$eval('#superrstudio_dataset option', o => o.map(x => x.textContent));
      if (!labels.includes('fish_tbl (tibble)') || !labels.includes('fish_dt (data.table)'))
         throw new Error('tibble/data.table not offered: ' + JSON.stringify(labels));
      await selectDataset(page, 'fish_dt');
      await choose(page, '#superrstudio_x', 'length cm');
      await choose(page, '#superrstudio_y', 'mass_g');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const dtCode = await page.locator('#superrstudio_code').inputValue();
      if (!dtCode.includes('ggplot2::ggplot(fish_dt, ')) throw new Error('data.table code: ' + dtCode);
      log('PASS tibble and data.table offered; preview from a data.table');
   }

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
   await choose(page, '#superrstudio_x', 'length cm');
   await choose(page, '#superrstudio_y', 'mass_g');
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

      // The editor is non-modal: no glass overlay, and the console works while
      // it is open. Changing the data there makes the selection stale, which
      // the editor refuses until the data is refreshed.
      const glass = await page.evaluate(() => [...document.querySelectorAll('.gwt-PopupPanelGlass')]
         .some(g => g.offsetParent !== null));
      if (glass) throw new Error('a modal glass overlay is shown');
      await check(page, `fish$mass_g[1] <- 99`, 'CONSOLE_USABLE_WITH_EDITOR_OPEN');
      await page.locator('#rstudio_superrstudio_preview').click();
      const stale = await waitStatus(page, /Dataset changed after selection/);
      log('PASS stale data refused while the editor stays open:', stale);
      await check(page, `fish <- fish_original`, 'DATA_RESTORED');
      await page.locator('#rstudio_superrstudio_refresh').click();
      await selectDataset(page, 'fish');
      await choose(page, '#superrstudio_x', 'length cm');
      await choose(page, '#superrstudio_y', 'mass_g');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      log('PASS refresh after the change; preview works again (non-modal editor)');
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
      await choose(page, '#superrstudio_x', 'length cm');
      await choose(page, '#superrstudio_y', 'mass_g');
      if (await page.locator('#superrstudio_undo').isEnabled()) throw new Error('undo enabled before any change');
      const title = 'Fish "length" vs mass';
      await type(page, '#superrstudio_title', title);
      await page.locator('#superrstudio_title').press('Tab');            // commits the value
      await type(page, '#superrstudio_xlabel', 'Length (cm)');
      await page.locator('#superrstudio_xlabel').press('Tab');
      await choose(page, '#superrstudio_colour', '#0072B2');
      await choose(page, '#superrstudio_size', '3');
      await choose(page, '#superrstudio_alpha', '0.6');
      await choose(page, '#superrstudio_theme', 'classic');
      await choose(page, '#superrstudio_theme', 'bw');
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
                          'ggplot2::theme_classic()', 'SuperRStudio scatter v4'])
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
      await choose(page, '#superrstudio_x', 'age');
      await choose(page, '#superrstudio_y', 'size');
      if (await page.locator('#superrstudio_line_order').isEnabled()) throw new Error('line order enabled for points');
      await choose(page, '#superrstudio_geometry', 'lines_points');
      if (!(await page.locator('#superrstudio_line_order').isEnabled())) throw new Error('line order disabled for lines');
      const hint = await page.locator('#superrstudio_order_hint').innerText();
      if (!/increasing X/.test(hint)) throw new Error('order hint missing: ' + hint);
      await choose(page, '#superrstudio_line_type', 'dashed');
      await choose(page, '#superrstudio_fit', 'lm');
      await choose(page, '#superrstudio_fit_level', '0.9');
      await choose(page, '#superrstudio_fit_colour', '#D55E00');
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
      await choose(page, '#superrstudio_fit', 'loess');
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
      await choose(page, '#superrstudio_kind', 'histogram');
      if (await page.locator('#superrstudio_y').isVisible()) throw new Error('Y shown for a histogram');
      if (!(await page.locator('#superrstudio_bins').isVisible())) throw new Error('bins hidden for a histogram');
      if (await page.locator('#superrstudio_fit').isVisible()) throw new Error('fit shown for a histogram');
      await choose(page, '#superrstudio_x', 'size');
      await choose(page, '#superrstudio_bins', '10');
      await choose(page, '#superrstudio_colour_by', 'site');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const histCode = await page.locator('#superrstudio_code').inputValue();
      fs.writeFileSync(path.join(evidence, 'generated-histogram.R'), histCode);
      for (const part of ['SuperRStudio histogram v4', 'ggplot2::aes(x = .data[["size"]], fill = .data[["site"]])',
                          'ggplot2::geom_histogram(bins = 10)', 'ggplot2::scale_fill_viridis_d()'])
         if (!histCode.includes(part)) throw new Error('histogram code lacks ' + part);
      const histText = await page.locator('#superrstudio_model').innerText();
      if (!/n = 8 finite values \(0 non-finite removed\); 10 bins/.test(histText)) throw new Error('histogram summary: ' + histText);
      await page.waitForTimeout(1500);
      await shot(page, '2e-histogram');
      log('PASS histogram (variable, bins, fill column, summary)');

      // Boxplot: numeric response by a group, outliers hidden, observations overlaid.
      await choose(page, '#superrstudio_kind', 'boxplot');
      if (!(await page.locator('#superrstudio_show_outliers').isVisible())) throw new Error('outlier option hidden');
      await choose(page, '#superrstudio_x', 'site');
      await choose(page, '#superrstudio_y', 'size');
      await choose(page, '#superrstudio_colour_by', '');
      await page.locator('#superrstudio_show_points input').check();   // GWT CheckBox: id on the wrapper span
      await choose(page, '#superrstudio_fill', '#56B4E9');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const boxCode = await page.locator('#superrstudio_code').inputValue();
      fs.writeFileSync(path.join(evidence, 'generated-boxplot.R'), boxCode);
      for (const part of ['SuperRStudio boxplot v4', 'ggplot2::aes(x = .data[["site"]], y = .data[["size"]])',
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

      // Bar chart of counts and a density curve.
      dialog = await openDialog(page);
      await selectDataset(page, 'growth');
      await choose(page, '#superrstudio_kind', 'bar');
      if (await page.locator('#superrstudio_y').isVisible()) throw new Error('Y shown for a bar chart');
      await choose(page, '#superrstudio_x', 'site');
      await choose(page, '#superrstudio_bar_position', 'dodge');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const barCode = await page.locator('#superrstudio_code').inputValue();
      const barText = await page.locator('#superrstudio_model').innerText();
      if (!barCode.includes('ggplot2::geom_bar(position = "dodge")') || !/north: n = 4\nsouth: n = 4/.test(barText))
         throw new Error('bar chart: ' + barCode + '\n' + barText);
      await choose(page, '#superrstudio_kind', 'density');
      if (!(await page.locator('#superrstudio_adjust').isVisible())) throw new Error('adjust hidden for density');
      await choose(page, '#superrstudio_x', 'size');
      await choose(page, '#superrstudio_adjust', '1.5');
      await choose(page, '#superrstudio_fill', '#009E73');
      await choose(page, '#superrstudio_alpha', '0.6');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const densityCode = await page.locator('#superrstudio_code').inputValue();
      const densityText = await page.locator('#superrstudio_model').innerText();
      const bandwidth = /n = 8; bandwidth ([0-9.e-]+)/.exec(densityText);
      if (!densityCode.includes('ggplot2::geom_density(adjust = 1.5, fill = "#009E73", alpha = 0.6)') || !bandwidth)
         throw new Error('density: ' + densityCode + '\n' + densityText);
      await page.waitForTimeout(1500);
      await shot(page, '2g-density');
      await closeDialog(page);
      await check(page, `stopifnot(isTRUE(all.equal(${bandwidth[1]}, signif(stats::bw.nrd0(growth$size) * 1.5, 4))))`,
         'DENSITY_BANDWIDTH_MATCHES_REFERENCE');
      log('PASS bar chart (counts, dodge) and density (adjust, bandwidth equals bw.nrd0 × 1.5)');

      // Colour by a character column: fixed colour is disabled, viridis scale emitted.
      dialog = await openDialog(page);
      await selectDataset(page, 'fish');
      const colourColumns = await page.$$eval('#superrstudio_colour_by option', o => o.map(x => x.value));
      if (JSON.stringify(colourColumns) !== JSON.stringify(['', 'sample', 'site', 'length cm', 'mass_g', 'observed', 'date', 'note']))
         throw new Error('unexpected colour columns ' + JSON.stringify(colourColumns));
      await choose(page, '#superrstudio_x', 'length cm');
      await choose(page, '#superrstudio_y', 'mass_g');
      await choose(page, '#superrstudio_colour', '#E69F00');
      await choose(page, '#superrstudio_colour_by', 'site');
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

      // Interactive editing on the preview itself: right-click a point series,
      // change its colour and size; undo/redo; axis title; line layer;
      // keyboard access. Live re-renders never add plots to the Plots pane.
      dialog = await openDialog(page);
      await selectDataset(page, 'growth');
      await choose(page, '#superrstudio_x', 'age');
      await choose(page, '#superrstudio_y', 'size');
      const preview = page.locator('#superrstudio_interactive img');
      const previewSrc = () => preview.getAttribute('src');
      const freshPreview = () => page.waitForFunction(() => {
         const image = document.querySelector('#superrstudio_interactive img');
         return image && image.offsetParent !== null && image.src.startsWith('data:image/svg+xml') &&
                image.style.opacity !== '0.5';
      }, null, {timeout: 60000});
      await freshPreview();
      const baseCode = await waitCode(page, /ggplot2::geom_point\(\)/);
      const plotsBefore = await plotImage();
      const map = await plotMap(page, baseCode,
         "Filter(function(e) e$role == 'points', srs_map$elements)[[1]]$coords[1:2], " +
         "Filter(function(r) r$role == 'x_label', srs_map$regions)[[1]]$box", 'SRS_POINTS_MAP');
      let box = await preview.boundingBox();
      const at = (fx, fy) => [box.x + fx * box.width, box.y + fy * box.height];
      const popup = page.locator('#superrstudio_element_popup');
      let srcBefore = await previewSrc();
      await page.mouse.click(...at(map[0], map[1]), {button: 'right'});
      await popup.waitFor({state: 'visible'});
      if (!(await popup.innerText()).startsWith('Points')) throw new Error('popup: ' + await popup.innerText());
      await shot(page, '5a-point-popup');
      await choose(page, '#superrstudio_popup_colour', '#D55E00');
      await waitCode(page, /ggplot2::geom_point\(colour = "#D55E00"\)/);
      await choose(page, '#superrstudio_popup_size', '4');
      const pointCode = await waitCode(page, /ggplot2::geom_point\(colour = "#D55E00", size = 4\)/);
      await freshPreview();
      if (await previewSrc() === srcBefore) throw new Error('preview not re-rendered after the edit');
      if (await page.inputValue('#superrstudio_colour') !== '#D55E00' || await page.inputValue('#superrstudio_size') !== '4')
         throw new Error('editor form not synchronized with the popup');
      await shot(page, '5b-point-edited');
      await page.locator('#superrstudio_popup_size').press('Escape');
      await popup.waitFor({state: 'detached'});
      log('PASS right-click on points: colour and size edited in place; form, code and preview updated');

      await page.locator('#superrstudio_undo').click();
      await waitCode(page, /ggplot2::geom_point\(colour = "#D55E00"\) \+|ggplot2::geom_point\(colour = "#D55E00"\)\n/);
      if (!(await page.locator('#superrstudio_redo').isEnabled())) throw new Error('redo disabled after undo');
      await page.locator('#superrstudio_redo').click();
      await waitCode(page, /ggplot2::geom_point\(colour = "#D55E00", size = 4\)/);
      log('PASS undo and redo of interactive edits');

      await page.mouse.click(...at((map[2] + map[4]) / 2, (map[3] + map[5]) / 2), {button: 'right'});
      await popup.waitFor({state: 'visible'});
      if (!(await popup.innerText()).startsWith('X axis title')) throw new Error('axis popup: ' + await popup.innerText());
      await type(page, '#superrstudio_popup_x_label', 'Age (years)');
      await page.locator('#superrstudio_popup_x_label').press('Enter');
      await waitCode(page, /ggplot2::labs\(x = "Age \(years\)"\)/);
      if (await page.inputValue('#superrstudio_xlabel') !== 'Age (years)') throw new Error('x label not synchronized');
      await page.locator('#superrstudio_popup_x_label').press('Escape');
      await popup.waitFor({state: 'detached'});
      log('PASS right-click on the X axis title edits it');

      await choose(page, '#superrstudio_geometry', 'lines_points');
      const linesCode = await waitCode(page, /ggplot2::geom_line\(\)/);
      await freshPreview();
      const segment = await plotMap(page, linesCode,
         "Filter(function(e) e$role == 'lines', srs_map$elements)[[1]]$coords[1:4]", 'SRS_LINES_MAP');
      box = await preview.boundingBox();
      await page.mouse.click(...at((segment[0] + segment[2]) / 2, (segment[1] + segment[3]) / 2), {button: 'right'});
      await popup.waitFor({state: 'visible'});
      if (!(await popup.innerText()).startsWith('Connected lines')) throw new Error('line popup: ' + await popup.innerText());
      await choose(page, '#superrstudio_popup_line_type', 'dotted');
      const lineCode = await waitCode(page, /ggplot2::geom_line\(linetype = "dotted"\)/);
      await page.locator('#superrstudio_popup_line_type').press('Escape');
      await popup.waitFor({state: 'detached'});
      log('PASS right-click on a line layer edits its line type');

      // keyboard: arrow keys select elements, Enter opens the properties
      await page.locator('#superrstudio_interactive').focus();
      await page.keyboard.press('ArrowRight');
      await waitStatus(page, /^Selected: /);
      await page.keyboard.press('Enter');
      await popup.waitFor({state: 'visible'});
      await page.keyboard.press('Escape');
      await popup.waitFor({state: 'detached'});
      log('PASS keyboard selection and properties (arrow keys, Enter, Escape)');
      if (await plotImage() !== plotsBefore) throw new Error('live re-rendering added a plot to the Plots pane');
      await freshPreview();
      await shot(page, '5c-interactive-final');
      await closeDialog(page);
      fs.writeFileSync(path.join(evidence, 'generated-interactive.R'), lineCode);
      await check(page,
         `srs_plot <- eval(parse(text = ${JSON.stringify(lineCode)})); srs_point <- srs_plot$layers[[2]]$aes_params; ` +
         `stopifnot(identical(srs_point$colour, '#D55E00'), identical(srs_point$size, 4), ` +
         `identical(srs_plot$layers[[1]]$aes_params$linetype, 'dotted'), identical(srs_plot$labels$x, 'Age (years)'), ` +
         `identical(growth, growth_original))`,
         'INTERACTIVE_EDITS_REPRODUCE');

      // Axes and facets: log scale, facets by a column, statistics per panel;
      // a facet strip and the Y axis are edited by right-click.
      dialog = await openDialog(page);
      await selectDataset(page, 'growth');
      await choose(page, '#superrstudio_x', 'age');
      await choose(page, '#superrstudio_y', 'size');
      await choose(page, '#superrstudio_fit', 'lm');
      await page.locator('#superrstudio_tab_axes').click();
      if (await page.getAttribute('#superrstudio_tab_axes', 'aria-selected') !== 'true') throw new Error('axes tab not selected');
      await choose(page, '#superrstudio_y_scale', 'log10');
      await choose(page, '#superrstudio_facet_by', 'site');
      const facetCode = await waitCode(page, /ggplot2::facet_wrap\(ggplot2::vars\(\.data\[\["site"\]\]\)\)/);
      if (!facetCode.includes('ggplot2::scale_y_log10()') || !facetCode.includes('"schema_version":4'))
         throw new Error('axis code: ' + facetCode);
      const facetModel = await page.locator('#superrstudio_model').innerText();
      if (!/^north: n = 4; log10\(size\) = /m.test(facetModel) || !/^south: n = 4; log10\(size\) = /m.test(facetModel) ||
          !/computed on the log10 scale/.test(facetModel))
         throw new Error('per-panel log fit summary: ' + facetModel);
      await freshPreview();
      const strips = await plotMap(page, facetCode.split('\n# Linear model')[0],
         "Filter(function(r) r$role == 'strip', srs_map$regions)[[1]]$box, " +
         "Filter(function(r) r$role == 'y_axis', srs_map$regions)[[1]]$box", 'SRS_FACET_MAP');
      box = await preview.boundingBox();
      await page.mouse.click(...at((strips[0] + strips[2]) / 2, (strips[1] + strips[3]) / 2), {button: 'right'});
      await popup.waitFor({state: 'visible'});
      if (!(await popup.innerText()).startsWith('Facet labels')) throw new Error('strip popup: ' + await popup.innerText());
      await page.selectOption('#superrstudio_popup_facet_scales', 'free_y');
      await waitCode(page, /ggplot2::facet_wrap\(ggplot2::vars\(\.data\[\["site"\]\]\), scales = "free_y"\)/);
      await page.locator('#superrstudio_popup_facet_scales').press('Escape');
      await popup.waitFor({state: 'detached'});
      await freshPreview();
      box = await preview.boundingBox();
      await page.mouse.click(...at((strips[4] + strips[6]) / 2, (strips[5] + strips[7]) / 2), {button: 'right'});
      await popup.waitFor({state: 'visible'});
      if (!(await popup.innerText()).startsWith('Y axis')) throw new Error('y axis popup: ' + await popup.innerText());
      await page.fill('#superrstudio_popup_y_min', '5');
      await page.locator('#superrstudio_popup_y_min').press('Enter');
      const axisCode = await waitCode(page, /ggplot2::coord_cartesian\(ylim = c\(5, NA\)\)/);
      await page.locator('#superrstudio_popup_y_min').press('Escape');
      await popup.waitFor({state: 'detached'});
      await freshPreview();
      await shot(page, '6-axes-facets');
      log('PASS axes and facets: log Y, facet panels with per-panel fits, strip and Y axis edited by right-click');
      await closeDialog(page);
      fs.writeFileSync(path.join(evidence, 'generated-axes-facets.R'), axisCode);
      await check(page,
         `srs_built <- ggplot2::ggplot_build(eval(parse(text = ${JSON.stringify(axisCode.split('\n# Linear model')[0])}))); ` +
         `srs_range <- srs_built$layout$panel_params[[1]]$y.range; stopifnot(nrow(srs_built$layout$layout) == 2L, ` +
         `isTRUE(all.equal(srs_range[1] + 0.05 * diff(srs_range) / 1.1, log10(5))), ` +
         `isTRUE(all.equal(unname(stats::coef(stats::lm(log10(size) ~ age, data = growth[growth$site == 'north', ]))[2]), ` +
         `unname(stats::coef(stats::lm(y ~ x, data = srs_built$data[[2]][srs_built$data[[2]]$PANEL == 1, c('x', 'y')]))[2]))), ` +
         `identical(growth, growth_original))`,
         'AXES_FACETS_REPRODUCE');

      // Escape closes the editor (handled only for its own content).
      dialog = await openDialog(page);
      // (a control disabled while a request runs cannot hold the focus)
      await page.waitForFunction(() => !document.getElementById('superrstudio_dataset').disabled);
      await page.locator('#superrstudio_dataset').press('Escape');
      await page.getByRole('dialog').waitFor({state: 'detached'});
      log('PASS Escape closes the editor');

      // Export opens the same code in a new, unsaved R script.
      dialog = await openDialog(page);
      await selectDataset(page, 'fish');
      await choose(page, '#superrstudio_x', 'length cm');
      await choose(page, '#superrstudio_y', 'mass_g');
      await page.locator('#rstudio_superrstudio_export').click();
      await page.getByRole('dialog').waitFor({state: 'detached'});
      await page.waitForFunction(() => window.rstudio.documents.activeEditor()?.getValue().includes('SuperRStudio scatter v4'));
      const script = await page.evaluate(() => window.rstudio.documents.activeEditor().getValue());
      if (script !== code) throw new Error('exported script differs from previewed code:\n' + script);
      log('PASS export opens identical code in a new R script');
      await shot(page, '3-exported-script');

      // Reopen a plot from its code: the active script holds the earlier
      // boxplot's generated code; loading restores its specification and a
      // preview reproduces exactly the same code.
      await page.evaluate(text => window.rstudio.documents.activeEditor().setValue(text, 1), boxCode);
      dialog = await openDialog(page);
      await page.locator('#superrstudio_load').click();
      await waitStatus(page, /Settings loaded from the active script/);
      const restored = {
         dataset: await page.inputValue('#superrstudio_dataset'), kind: await page.inputValue('#superrstudio_kind'),
         x: await page.inputValue('#superrstudio_x'), y: await page.inputValue('#superrstudio_y'),
         fill: await page.inputValue('#superrstudio_fill'),
         points: await page.locator('#superrstudio_show_points input').isChecked()};
      if (JSON.stringify(restored) !== JSON.stringify({dataset: 'growth', kind: 'boxplot', x: 'site', y: 'size',
                                                        fill: '#56B4E9', points: true}))
         throw new Error('specification not restored: ' + JSON.stringify(restored));
      if (!(await page.locator('#superrstudio_undo').isEnabled())) throw new Error('loading is not undoable');
      await page.locator('#rstudio_superrstudio_preview').click();
      await waitStatus(page, /Plot created/);
      const reloaded = await page.locator('#superrstudio_code').inputValue();
      if (reloaded !== boxCode) throw new Error('reloaded code differs:\n' + reloaded + '\n---\n' + boxCode);
      await shot(page, '4-loaded-from-script');
      await closeDialog(page);
      log('PASS load from script restores the specification; preview reproduces identical code');
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
