// Ask a development desktop started with -DebugPort to quit the way a user
// would (no process killing): RStudio's quitSession command through the
// automation bridge when present (-Automation), otherwise closing the main
// window, which runs RStudio's normal close/quit handling.
// SPDX-License-Identifier: AGPL-3.0-only
//   node tools/superrstudio/dev-quit.cjs [port]
const {chromium} = require('playwright');
const port = process.argv[2] || process.env.SUPER_RSTUDIO_CDP_PORT || '19381';
(async () => {
   const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
   const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
   if (!page) throw new Error('No RStudio window found on port ' + port);
   const how = await page.evaluate(() => {
      if (window.rstudio?.commands?.quitSession)
      {
         window.rstudio.commands.quitSession();
         return 'quitSession command';
      }
      window.close();
      return 'window close';
   }).catch(() => 'requested (window closed during the call)');
   console.log('quit requested via', how);
})().catch(error => { console.error(error.message); process.exitCode = 1; })
   .finally(() => process.exit());
