// Verify the installed application in a disposable Windows Actions runner.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:19446');
  try {
    let page;
    for (let i = 0; i < 90 && !page; i++) {
      page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().startsWith('http:'));
      if (!page) await new Promise(resolve => setTimeout(resolve, 1000));
    }
    assert.ok(page, 'No desktop workbench');
    await page.waitForFunction(() => window.rstudio?.ready, null, {timeout: 120000});
    await page.locator('#superr_chat_ai_toggle').click();
    assert.equal(await page.locator('#superr_chat_ai_provider').isVisible(), true);
    const result = await page.evaluate(async () => ({
      prefs: await window.desktop.superrGetUpdatePrefs(),
      download: await window.desktop.superrDownloadUpdate('superr-v0.3.0', 'stable'),
    }));
    assert.ok(['stable', 'preview'].includes(result.prefs.channel));
    assert.deepEqual(result.download, {ok: false, reason: 'untrusted'});
    console.log('PASS installed workbench, Chat IA panel and updater fail-closed IPC');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
