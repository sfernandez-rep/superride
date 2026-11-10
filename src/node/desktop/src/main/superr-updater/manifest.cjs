// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const {constants} = require('node:fs');
const {parseVersion, compareVersions} = require('./releases.cjs');

// No production signing key is provisioned. Never replace this with a key
// supplied by the release server or by an unsigned local manifest.
const TRUSTED_KEYS = Object.freeze({});
const verifiedManifests = new WeakSet();

function verifyManifest(bytes, signature, keyId, currentVersion, channel, options = {}) {
  const keys = options.trustedKeys || TRUSTED_KEYS;
  if (!Buffer.isBuffer(bytes) || bytes.length === 0 || bytes.length > 16384 ||
      typeof keyId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(keyId) ||
      !Object.hasOwn(keys, keyId) || !Buffer.isBuffer(signature) || signature.length !== 64)
    throw new Error('Untrusted update manifest');
  let key;
  try { key = crypto.createPublicKey(keys[keyId]); } catch { throw new Error('Untrusted update manifest'); }
  if (key.asymmetricKeyType !== 'ed25519' || !crypto.verify(null, bytes, key, signature))
    throw new Error('Invalid update signature');
  let data;
  try { data = JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(bytes)); }
  catch { throw new Error('Invalid update manifest'); }
  const now = options.now ?? Date.now();
  if (!data || typeof data !== 'object' || Array.isArray(data) || data.schema !== 1 ||
      !['stable', 'preview'].includes(channel) || !parseVersion(currentVersion) ||
      typeof data.version !== 'string' || !parseVersion(data.version) ||
      compareVersions(data.version, currentVersion) <= 0 ||
      data.channel !== (parseVersion(data.version).pre.length ? 'preview' : 'stable') ||
      (channel === 'stable' && data.channel !== 'stable') || data.platform !== 'windows' || data.arch !== 'x64' ||
      data.artifact !== `SuperR-${data.version}-Windows-x64.exe` ||
      !Number.isSafeInteger(data.size) || data.size < 1 || data.size > 2 * 1024 * 1024 * 1024 ||
      typeof data.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(data.sha256) ||
      !Number.isSafeInteger(data.issued) || !Number.isSafeInteger(data.expires) ||
      data.issued > now || data.expires <= now || data.expires <= data.issued || data.expires - data.issued > 31 * 86400000)
    throw new Error('Invalid or expired update manifest');
  const manifest = Object.freeze({version:data.version, channel:data.channel, artifact:data.artifact, size:data.size, sha256:data.sha256});
  verifiedManifests.add(manifest);
  return manifest;
}

/** Check a downloaded file against an already verified manifest, without executing it. */
async function verifyArtifact(filename, manifest) {
  if (!manifest || !verifiedManifests.has(manifest)) throw new Error('Unverified update manifest');
  const info = await fs.lstat(filename);
  if (!info.isFile() || info.isSymbolicLink() || info.size !== manifest.size) throw new Error('Invalid update artifact');
  const file = await fs.open(filename, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.size !== manifest.size) throw new Error('Invalid update artifact');
    const hash = crypto.createHash('sha256');
    const buffer = Buffer.alloc(65536); let position = 0;
    while (position < manifest.size) {
      const part = await file.read(buffer, 0, Math.min(buffer.length, manifest.size - position), position);
      if (!part.bytesRead) throw new Error('Incomplete update artifact');
      hash.update(buffer.subarray(0, part.bytesRead)); position += part.bytesRead;
    }
    const after = await file.stat();
    if (after.size !== stat.size || after.mtimeMs !== stat.mtimeMs || hash.digest('hex') !== manifest.sha256)
      throw new Error('Update artifact integrity check failed');
  } finally { await file.close(); }
}

/** Download only an authenticated manifest's artifact, never execute it. */
async function downloadArtifact(manifest, privateRoot, request = fetch, signal) {
  if (!manifest || !verifiedManifests.has(manifest)) throw new Error('Unverified update manifest');
  if (!path.isAbsolute(privateRoot)) throw new Error('An absolute download directory is required');
  await fs.mkdir(privateRoot, {recursive:true, mode:0o700});
  const rootInfo = await fs.lstat(privateRoot);
  if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink()) throw new Error('Invalid download directory');
  const root = await fs.realpath(privateRoot);
  const directory = await fs.mkdtemp(path.join(root, 'superr-update-'));
  const filePath = path.join(directory, manifest.artifact);
  let file; let completed = false;
  try {
    let url = `https://github.com/sfernandez-rep/superride/releases/download/superr-v${manifest.version}/${manifest.artifact}`;
    let response;
    for (let i=0; i<4; i++) {
      const parsed = new URL(url);
      if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port ||
          !['github.com', 'release-assets.githubusercontent.com'].includes(parsed.hostname))
        throw new Error('Untrusted download destination');
      response = await request(url, {redirect:'manual', signal});
      if (![301,302,303,307,308].includes(response.status)) break;
      const location = response.headers.get('location');
      if (!location || i === 3) throw new Error('Invalid download redirect');
      url = new URL(location, url).href;
    }
    if (!response || !response.ok || !response.body) throw new Error('Update download failed');
    file = await fs.open(filePath, 'wx', 0o600);
    const reader = response.body.getReader();
    const hash = crypto.createHash('sha256'); let size = 0;
    try {
      for (;;) {
        const part = await reader.read();
        if (part.done) break;
        size += part.value.byteLength;
        if (size > manifest.size) { await reader.cancel(); throw new Error('Update artifact exceeds expected size'); }
        const bytes = Buffer.from(part.value); hash.update(bytes);
        let offset=0;
        while (offset < bytes.length) {
          const written = await file.write(bytes, offset, bytes.length-offset);
          if (!written.bytesWritten) throw new Error('Could not write update artifact');
          offset += written.bytesWritten;
        }
      }
    } finally { reader.releaseLock(); }
    signal?.throwIfAborted();
    if (size !== manifest.size || hash.digest('hex') !== manifest.sha256) throw new Error('Update artifact integrity check failed');
    await file.sync(); await file.close(); file = undefined;
    await verifyArtifact(filePath, manifest);
    completed = true;
    return filePath;
  } finally {
    if (file) await file.close();
    if (!completed) {
      const relative = path.relative(root, directory);
      const info = await fs.lstat(directory);
      if (!relative.startsWith('superr-update-') || relative.includes(path.sep) ||
          !info.isDirectory() || info.isSymbolicLink() || await fs.realpath(directory) !== directory)
        throw new Error('Invalid download cleanup target');
      await fs.rm(directory, {recursive:true, force:true});
    }
  }
}
module.exports = {verifyManifest, verifyArtifact, downloadArtifact};
