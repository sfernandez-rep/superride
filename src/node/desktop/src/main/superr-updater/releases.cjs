// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
'use strict';

const RELEASES_API = 'https://api.github.com/repos/sfernandez-rep/superride/releases?per_page=100';
const RELEASES_PAGE = 'https://github.com/sfernandez-rep/superride/releases';
const VERSION = /^(?:superr-v)?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

function parseVersion(input) {
  if (typeof input !== 'string' || input.length > 128) return null;
  const match = VERSION.exec(input);
  if (!match) return null;
  const core = match.slice(1, 4).map(Number);
  if (!core.every(Number.isSafeInteger)) return null;
  const pre = match[4] ? match[4].split('.') : [];
  if (pre.some(part => /^\d+$/.test(part) && (part.length > 15 || (part.length > 1 && part[0] === '0')))) return null;
  return {core, pre};
}

function compareVersions(left, right) {
  const a = parseVersion(left), b = parseVersion(right);
  if (!a || !b) throw new Error('Invalid SuperR version');
  for (let i = 0; i < 3; i++) if (a.core[i] !== b.core[i]) return a.core[i] < b.core[i] ? -1 : 1;
  if (!a.pre.length || !b.pre.length) return Math.sign(b.pre.length - a.pre.length);
  for (let i = 0; i < Math.min(a.pre.length, b.pre.length); i++) {
    const x = a.pre[i], y = b.pre[i];
    if (x === y) continue;
    const xn = /^\d+$/.test(x), yn = /^\d+$/.test(y);
    if (xn && yn) return Number(x) < Number(y) ? -1 : 1;
    if (xn !== yn) return xn ? -1 : 1;
    return x < y ? -1 : 1;
  }
  return Math.sign(a.pre.length - b.pre.length);
}

/** Select only public, properly tagged releases from the official repository. */
function selectRelease(releases, currentVersion, channel) {
  if (!parseVersion(currentVersion) || !['stable', 'preview'].includes(channel) || !Array.isArray(releases))
    throw new Error('Invalid update query');
  let newest = null;
  for (const item of releases) {
    if (!item || item.draft !== false || typeof item.tag_name !== 'string' || !item.tag_name.startsWith('superr-v') ||
        typeof item.prerelease !== 'boolean') continue;
    const version = parseVersion(item.tag_name);
    if (!version || Boolean(version.pre.length) !== item.prerelease || (channel === 'stable' && item.prerelease)) continue;
    if (compareVersions(item.tag_name, currentVersion) <= 0) continue;
    const expectedUrl = `${RELEASES_PAGE}/tag/${item.tag_name}`;
    if (item.html_url !== expectedUrl) continue;
    if (!newest || compareVersions(item.tag_name, newest.version) > 0)
      newest = {version: item.tag_name, url: expectedUrl, prerelease: item.prerelease,
        notes: typeof item.body === 'string' ? item.body.slice(0, 32768) : ''};
  }
  return newest;
}

async function checkForUpdates(currentVersion, channel, request = fetch, signal) {
  if (!parseVersion(currentVersion) || !['stable', 'preview'].includes(channel)) throw new Error('Invalid update query');
  const response = await request(RELEASES_API, {headers: {Accept: 'application/vnd.github+json'}, redirect: 'error',
    signal: signal || AbortSignal.timeout(15000)});
  if (!response.ok) throw new Error(`Release service error: ${response.status}`);
  // Cap the response before parsing, including when no content length is supplied.
  if (!response.body) throw new Error('Empty release response');
  const reader = response.body.getReader();
  const chunks = []; let length = 0;
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      length += part.value.byteLength;
      if (length > 2 * 1024 * 1024) { await reader.cancel(); throw new Error('Release response too large'); }
      chunks.push(part.value);
    }
  } finally { reader.releaseLock(); }
  let releases;
  try { releases = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks))); }
  catch { throw new Error('Invalid release response'); }
  return selectRelease(releases, currentVersion, channel);
}

module.exports = { RELEASES_PAGE, parseVersion, compareVersions, selectRelease, checkForUpdates };
