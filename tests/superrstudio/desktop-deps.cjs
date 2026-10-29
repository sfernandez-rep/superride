// Live desktop test of SuperR's on-demand installation of optional R
// packages. SPDX-License-Identifier: AGPL-3.0-only
//
// Started by tools/superrstudio/test-gui-scatter.ps1 -Scenario deps with a
// fresh, empty R library (SUPER_RSTUDIO_TEST_LIBRARY) and the local package
// repository (SUPER_RSTUDIO_TEST_REPO, from make-local-repo.R). Steps:
//   fresh     opening the plot editor without ggplot2 shows the dependency
//             dialog (package, why, dependencies, source, library); Cancel
//             keeps the editor and the IDE usable
//   stop      an installation stopped by the user (all 17 packages to go)
//   failure   a repository without the package (Install disabled, reason
//             shown) and a broken package file (installation fails with a
//             message, nothing reported as installed)
//   success   Install: the packages go into the session's first library, the
//             dialog closes and the editor continues (preview drawn)
//   repeat    reopening the editor does not prompt again
//   lfq       the length-frequency window names TropFishR; the IDE stays usable
//   renv      a real renv project loaded in the session: the project library
//             is the target and renv.lock is not changed
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const project = path.resolve(__dirname, '../..').replaceAll('\\', '/');
const evidence = path.join(project, '.cache/superrstudio/gui-scatter');
fs.mkdirSync(evidence, {recursive: true});
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const library = process.env.SUPER_RSTUDIO_TEST_LIBRARY;
const repo = process.env.SUPER_RSTUDIO_TEST_REPO;
const log = (...args) => console.log(...args);
const expect = (condition, message) => { if (!condition) throw new Error(message); };
const shot = (page, name) => page.screenshot({path: path.join(evidence, `deps-${name}.png`)});

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

const dialog = page => page.locator('#superrstudio_deps_dialog');
const text = async (page, selector) => (await page.locator(selector).innerText()).trim();
const waitText = (page, selector, pattern, timeout = 120000) => page.waitForFunction(([s, p]) =>
   new RegExp(p).test(document.querySelector(s)?.innerText || ''), [selector, pattern.source], {timeout});
const repos = name => `options(repos = c(LOCAL = 'file:///${repo}/${name}'))`;

async function openEditor(page)
{
   await page.evaluate(() => window.rstudio.commands.activateEnvironment());
   await page.locator('#rstudio_superrstudio_scatter').click();
   await page.locator('#superrstudio_dataset').waitFor({state: 'attached'});
}

async function closeEditor(page)
{
   const close = page.getByRole('dialog').filter({has: page.locator('#superrstudio_dataset')})
                     .getByRole('button', {name: 'Close'});
   await close.click();
   await page.locator('#superrstudio_dataset').waitFor({state: 'detached'});
}

(async () => {
   expect(library && repo, 'SUPER_RSTUDIO_TEST_LIBRARY and SUPER_RSTUDIO_TEST_REPO are required');
   const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
   let page;
   for (let i = 0; i < 120 && !page; i++)
   {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(resolve => setTimeout(resolve, 1000));
   }
   if (!page) throw new Error('window did not load');
   await page.waitForFunction(() => window.rstudio?.ready, null, {timeout: 120000});
   await page.waitForTimeout(1500);
   await page.evaluate(() => window.rstudio.errors.clear());
   await check(page, `stopifnot(normalizePath(.libPaths()[1], winslash = '/') == '${library}', ` +
                     `!nzchar(system.file(package = 'ggplot2'))); ${repos('full')}; ` +
                     `peces <- data.frame(talla = c(12, 15, 18, 22, 25, 30), peso = c(20, 41, 70, 125, 180, 310))`,
               'DEPS_FRESH_LIBRARY');

   // fresh: prompt with the plan; Cancel keeps everything usable
   await openEditor(page);
   await dialog(page).waitFor({timeout: 60000});
   await waitText(page, '#superrstudio_deps_details', /Library: /);
   const details = await text(page, '#superrstudio_deps_details');
   log('plan:\n' + details);
   expect(details.includes('ggplot2 3.4.0 or newer: not installed') && details.includes('ggplot2 draws the preview') &&
          /It also installs \d+ package\(s\)/.test(details) && details.includes('scales') &&
          details.includes(`file:///${repo}/full`) && details.includes(`Library: ${library}`), 'plan details: ' + details);
   expect(await page.locator('#rstudio_superrstudio_deps_install').isEnabled(), 'Install not enabled');
   await shot(page, '1-prompt');
   await page.locator('#rstudio_superrstudio_deps_cancel').click();
   await dialog(page).waitFor({state: 'detached'});
   await page.locator('#superrstudio_deps_hint').waitFor();
   expect((await text(page, '#superrstudio_deps_hint')).includes('needs ggplot2'), 'missing-package hint');
   await check(page, 'stopifnot(sum(1:10) == 55, !nzchar(system.file(package = "ggplot2")))', 'DEPS_CANCEL_NOTHING_INSTALLED');
   log('PASS fresh library: prompt with package, reason, dependencies, source and library; Cancel installs nothing');

   // stop an installation
   await page.locator('#rstudio_superrstudio_deps_open').click();
   await dialog(page).waitFor();
   await waitText(page, '#superrstudio_deps_details', /Library: /);
   await page.locator('#rstudio_superrstudio_deps_install').click();
   await page.locator('#rstudio_superrstudio_deps_stop').waitFor().catch(async e => {
      throw new Error('no Stop button; status: ' + await text(page, '#superrstudio_deps_status'));
   });
   await page.locator('#rstudio_superrstudio_deps_stop').click();
   await waitText(page, '#superrstudio_deps_status', /Installation stopped/);
   await page.locator('#rstudio_superrstudio_deps_cancel').click();
   await dialog(page).waitFor({state: 'detached'});
   log('PASS installation stopped by the user');

   // failure: not in the repository
   await run(page, repos('empty'));
   await page.locator('#rstudio_superrstudio_deps_open').click();
   await dialog(page).waitFor();
   await waitText(page, '#superrstudio_deps_status', /not available/);
   expect(!(await page.locator('#rstudio_superrstudio_deps_install').isEnabled()), 'Install enabled for an unavailable package');
   await page.locator('#rstudio_superrstudio_deps_cancel').click();
   await dialog(page).waitFor({state: 'detached'});
   // failure: a broken package file
   const broken = `${repo}/broken-test`;
   await run(page, `local({ src <- dirname(list.files('${repo}/full', 'PACKAGES$', recursive = TRUE, full.names = TRUE)[1]); ` +
                   `dst <- file.path('${broken}', substring(src, nchar('${repo}/full') + 2)); unlink('${broken}', recursive = TRUE); ` +
                   `dir.create(dst, recursive = TRUE); invisible(file.copy(list.files(src, full.names = TRUE), dst)); ` +
                   `writeBin(as.raw(1:100), list.files(dst, '^ggplot2_', full.names = TRUE)) }); ` +
                   `options(repos = c(LOCAL = 'file:///${broken}'))`);
   await page.locator('#rstudio_superrstudio_deps_open').click();
   await dialog(page).waitFor();
   await waitText(page, '#superrstudio_deps_details', /Library: /);
   await page.locator('#rstudio_superrstudio_deps_install').click();
   await waitText(page, '#superrstudio_deps_status', /The installation failed/, 300000);
   await shot(page, '2-failed');
   await page.locator('#rstudio_superrstudio_deps_cancel').click();
   await dialog(page).waitFor({state: 'detached'});
   await check(page, 'stopifnot(!nzchar(system.file(package = "ggplot2")))', 'DEPS_FAILURE_NOT_INSTALLED');
   log('PASS failures: unavailable package refused with a reason; broken package fails with a message');

   // success: install, then the editor continues
   await run(page, repos('full'));
   await page.locator('#rstudio_superrstudio_deps_open').click();
   await dialog(page).waitFor();
   await waitText(page, '#superrstudio_deps_details', /Library: /);
   await page.locator('#rstudio_superrstudio_deps_install').click();
   await waitText(page, '#superrstudio_deps_status', /Installing/);
   await shot(page, '3-installing');
   await dialog(page).waitFor({state: 'detached', timeout: 600000});
   await page.locator('#superrstudio_deps_hint').waitFor({state: 'hidden'});
   await check(page, `stopifnot(normalizePath(dirname(system.file(package = 'ggplot2')), winslash = '/') == '${library}')`,
               'DEPS_INSTALLED_INTO_SESSION_LIBRARY');
   await page.waitForFunction(() => [...document.getElementById('superrstudio_dataset').options].some(o => o.value === 'peces'),
                              null, {timeout: 60000});
   await page.selectOption('#superrstudio_dataset', 'peces');
   await page.waitForFunction(() => [...document.getElementById('superrstudio_x').options].some(o => o.value === 'talla'));
   await page.selectOption('#superrstudio_x', 'talla');
   await page.selectOption('#superrstudio_y', 'peso');
   await page.waitForFunction(() => document.querySelector('#superrstudio_interactive img')?.src, null, {timeout: 120000});
   await shot(page, '4-resumed');
   log('PASS installation succeeded: packages in the session library, editor continued and drew the preview');

   // no repeated prompt once installed
   await closeEditor(page);
   await openEditor(page);
   await page.waitForTimeout(4000);
   expect(!(await dialog(page).count()), 'prompted again for an installed package');
   await closeEditor(page);
   log('PASS no prompt when the package is installed');

   // length-frequency window: TropFishR named; the window and IDE stay usable
   await page.evaluate(() => window.rstudio.commands.activateEnvironment());
   await page.locator('#rstudio_superrstudio_lfq').click();
   await dialog(page).waitFor({timeout: 60000});
   await waitText(page, '#superrstudio_deps_details', /Library: /);
   const lfqDetails = await text(page, '#superrstudio_deps_details');
   expect(lfqDetails.includes('TropFishR 1.6.0 or newer: not installed') && lfqDetails.includes('TropFishR performs the analyses'),
          'LFQ plan: ' + lfqDetails);
   await waitText(page, '#superrstudio_deps_status', /not available/);
   await page.locator('#rstudio_superrstudio_deps_cancel').click();
   await dialog(page).waitFor({state: 'detached'});
   expect(await page.locator('#rstudio_superrstudio_lfq_deps_open').isVisible(), 'LFQ install button');
   await page.keyboard.press('Escape');
   await check(page, 'stopifnot(sum(1:4) == 10)', 'DEPS_LFQ_CANCEL_IDE_USABLE');
   log('PASS length-frequency window names TropFishR; cancelled; IDE usable');

   // renv: a real renv project loaded in this session
   const renvLib = `${library}-renv-tool`;
   const proj = `${library}-renv-project`;
   await check(page,
      `unlink(c('${renvLib}', '${proj}'), recursive = TRUE); dir.create('${renvLib}'); dir.create('${proj}'); ` +
      `utils::install.packages('renv', lib = '${renvLib}', repos = 'file:///${repo}/full', type = .Platform$pkgType, quiet = TRUE); ` +
      `.libPaths(c('${renvLib}', .libPaths())); ` +
      `invisible(capture.output(renv::init(project = '${proj}', bare = TRUE, restart = FALSE, load = FALSE))); ` +
      `invisible(capture.output(renv::load('${proj}', quiet = TRUE))); ` +
      `invisible(capture.output(renv::snapshot(project = '${proj}', prompt = FALSE))); ` +
      `srs_lock <- tools::md5sum('${proj}/renv.lock'); ${repos('full')}; ` +
      // lib.loc: a loaded namespace would otherwise be found outside .libPaths()
      `stopifnot(!nzchar(system.file(package = 'ggplot2', lib.loc = .libPaths())))`,
      'DEPS_RENV_PROJECT_LOADED');
   await openEditor(page);
   await dialog(page).waitFor({timeout: 60000});
   await waitText(page, '#superrstudio_deps_details', /Library: /);
   const renvDetails = await text(page, '#superrstudio_deps_details');
   expect(renvDetails.includes('This project uses renv') && renvDetails.includes(proj), 'renv plan: ' + renvDetails);
   await shot(page, '5-renv');
   await page.locator('#rstudio_superrstudio_deps_install').click();
   await dialog(page).waitFor({state: 'detached', timeout: 600000});
   await check(page,
      `stopifnot(startsWith(normalizePath(system.file(package = 'ggplot2', lib.loc = .libPaths()), winslash = '/'), normalizePath('${proj}', winslash = '/')), ` +
      `identical(tools::md5sum('${proj}/renv.lock'), srs_lock))`,
      'DEPS_RENV_PROJECT_LIBRARY_LOCK_UNCHANGED');
   log('PASS renv project: installed into the project library; renv.lock unchanged');

   const errors = await page.evaluate(() => window.rstudio.errors.list());
   expect(!errors.length, 'client exceptions: ' + JSON.stringify(errors));
   log('PASS no client exceptions');
   log('DESKTOP_DEPS_PASS');
})().catch(error => { console.error(error.message); process.exitCode = 1; }).finally(() => process.exit());
