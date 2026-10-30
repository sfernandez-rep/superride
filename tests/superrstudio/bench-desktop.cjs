// Desktop measurements for tools/superrstudio/bench.ps1. SPDX-License-Identifier: AGPL-3.0-only
//
//   node tests/superrstudio/bench-desktop.cjs <launch-epoch-ms> <on|off>
//
// Prints one line "BENCH {json}" with: ready_ms (desktop process start to
// window.rstudio.ready), console round trips (20 x invisible(1); median and
// max in ms) and, with SuperRStudio features on, the plot editor's preview
// latency for 100,000-row data (selection to new preview image; includes the
// editor's 250 ms settle delay before rendering).
const {chromium} = require('playwright');

const launched = Number(process.argv[2]);
const features = process.argv[3] === 'on';
const port = process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
const median = values => { const s = [...values].sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; };

async function run(page, command)
{
   const before = await page.evaluate(text => {
      window.rstudio.commands.activateConsole();
      const editor = document.getElementById('rstudio_console_input').env.editor;
      editor.setValue(text, 1);
      editor.focus();
      return window.rstudio.console.promptCount;
   }, command);
   const started = Date.now();
   await page.keyboard.press('Enter');
   await page.waitForFunction(n => window.rstudio.console.promptCount > n, before, {timeout: 120000, polling: 'raf'});
   return Date.now() - started;
}

(async () => {
   let browser;
   for (let i = 0; i < 600 && !browser; i++)
   {
      try { browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`); }
      catch { await new Promise(resolve => setTimeout(resolve, 100)); }
   }
   let page;
   for (let i = 0; i < 1200 && !page; i++)
   {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(resolve => setTimeout(resolve, 100));
   }
   await page.waitForFunction(() => window.rstudio?.ready, null, {timeout: 180000, polling: 100});
   const ready = Date.now() - launched;
   await run(page, 'invisible(1)');   // first command warms the console path
   const trips = [];
   for (let i = 0; i < 20; i++) trips.push(await run(page, 'invisible(1)'));
   const result = {ready_ms: ready, console_median_ms: median(trips), console_max_ms: Math.max(...trips)};

   if (features)
   {
      await run(page, "set.seed(1); bench_ts <- data.frame(day = as.Date('2000-01-01') + 0:99999, " +
                      "v = cumsum(rnorm(100000)), w = rnorm(100000))");
      await page.evaluate(() => window.rstudio.commands.activateEnvironment());
      const opened = Date.now();
      await page.locator('#rstudio_superrstudio_scatter').click();
      await page.waitForFunction(() => document.getElementById('superrstudio_dataset')?.options.length > 0);
      result.editor_open_ms = Date.now() - opened;
      // time from the last change to the preview of that change (the code
      // and image are replaced together when the render answers)
      const preview = async (marker, change) => {
         const started = Date.now();
         await change();
         await page.waitForFunction(m => (document.getElementById('superrstudio_code')?.value || '').includes(m) &&
            !!document.querySelector('#superrstudio_interactive img')?.src, marker, {timeout: 120000, polling: 50});
         return Date.now() - started;
      };
      await page.selectOption('#superrstudio_dataset', 'bench_ts');
      await page.waitForFunction(() => [...document.getElementById('superrstudio_x').options].some(o => o.value === 'day'));
      await page.selectOption('#superrstudio_x', 'day');
      await page.selectOption('#superrstudio_y', 'v');
      result.preview_lines_100k_ms = await preview('ggplot2::geom_line()', () => page.selectOption('#superrstudio_geometry', 'lines'));
      result.preview_lines_format = await page.evaluate(() => document.querySelector('#superrstudio_interactive img').src.slice(5, 18));
      await page.selectOption('#superrstudio_x', 'w');
      result.preview_points_100k_ms = await preview('ggplot2::geom_point()', () => page.selectOption('#superrstudio_geometry', 'points'));
      result.preview_points_format = await page.evaluate(() => document.querySelector('#superrstudio_interactive img').src.slice(5, 18));
      await page.getByRole('dialog').getByRole('button', {name: 'Close'}).click();
   }
   result.client_errors = (await page.evaluate(() => window.rstudio.errors.list())).length;
   console.log('BENCH ' + JSON.stringify(result));
   await browser.close();
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => process.exit());
