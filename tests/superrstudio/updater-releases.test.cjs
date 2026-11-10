const test = require('node:test');
const assert = require('node:assert/strict');
const {compareVersions, parseVersion, selectRelease, checkForUpdates} = require('../../src/node/desktop/src/main/superr-updater/releases.cjs');
const release = (version, prerelease = false) => ({tag_name:'superr-v' + version, draft:false, prerelease,
  html_url:'https://github.com/sfernandez-rep/superride/releases/tag/superr-v' + version, body:'Release notes'});

test('version ordering handles stable, preview and invalid versions', () => {
  assert.equal(compareVersions('0.1.1-preview.2','0.1.1-preview.10'), -1);
  assert.equal(compareVersions('0.1.1-preview.1','0.1.1'), -1);
  assert.equal(compareVersions('0.1.1+one','0.1.1+two'), 0);
  assert.equal(parseVersion('0.1.1-preview.01'), null);
  assert.throws(() => compareVersions('bad','0.1.1'), /Invalid/);
});

test('selects only newer official releases for the chosen channel', () => {
  const releases = [release('0.1.2'), release('0.2.0-preview.1', true), release('0.1.1'),
    {...release('9.0.0'), html_url:'https://attacker.invalid/'}, {...release('8.0.0'), draft:true}];
  assert.equal(selectRelease(releases,'0.1.1','stable').version, 'superr-v0.1.2');
  assert.equal(selectRelease(releases,'0.1.1','preview').version, 'superr-v0.2.0-preview.1');
  assert.equal(selectRelease(releases,'9.0.0','preview'), null);
  assert.throws(() => selectRelease(releases,'0.1.1','unknown'), /Invalid/);
});

test('fetch checks failures and parses release data without credentials', async () => {
  const response = data => new Response(JSON.stringify(data), {status:200});
  const result = await checkForUpdates('0.1.0','preview', async (url, options) => {
    assert.match(url, /^https:\/\/api\.github\.com\/repos\/sfernandez-rep\/superride\/releases\?/);
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, undefined);
    return response([release('0.1.1-preview.1', true)]);
  });
  assert.equal(result.version, 'superr-v0.1.1-preview.1');
  await assert.rejects(checkForUpdates('0.1.0','stable', async () => new Response('', {status:503})), /503/);
  await assert.rejects(checkForUpdates('0.1.0','stable', async () => new Response('not json')), /Invalid release/);
});

test('checks subsequent release pages before selecting the newest version', async () => {
  let calls = 0;
  const first = Array.from({length:100}, () => release('0.1.1'));
  const result = await checkForUpdates('0.1.0', 'stable', async url => {
    calls++;
    return new Response(JSON.stringify(url.endsWith('page=1') ? first : [release('0.3.0')]));
  });
  assert.equal(calls,2);
  assert.equal(result.version,'superr-v0.3.0');
});
