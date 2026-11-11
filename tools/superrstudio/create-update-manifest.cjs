// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {parseVersion} = require('../../src/node/desktop/src/main/superr-updater/releases.cjs');

async function main() {
  const [version, artifact, output] = process.argv.slice(2);
  const parsed = parseVersion(version);
  const keyId = process.env.SUPERR_UPDATE_KEY_ID;
  if (!version || version.startsWith('superr-v') || !parsed || !artifact || !output || process.argv.length !== 5 ||
      !keyId || !/^[A-Za-z0-9_-]{1,64}$/.test(keyId) || path.basename(artifact) !== `SuperR-${version}-Windows-x64.exe`)
    throw new Error('Expected version, matching Windows x64 installer, and output path');
  const before = await fs.promises.lstat(artifact);
  if (!before.isFile() || before.isSymbolicLink() || before.size < 1 || before.size > 2 * 1024 * 1024 * 1024)
    throw new Error('Invalid installer');
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(artifact)) hash.update(chunk);
  const after = await fs.promises.lstat(artifact);
  if (!after.isFile() || after.isSymbolicLink() || before.size !== after.size || before.mtimeMs !== after.mtimeMs)
    throw new Error('Installer changed while hashing');
  const issued = Date.now();
  const manifest = {schema:1, keyId, version, channel:parsed.pre.length ? 'preview' : 'stable', platform:'windows', arch:'x64',
    artifact:path.basename(artifact), size:before.size, sha256:hash.digest('hex'), issued, expires:issued + 30 * 86400000};
  await fs.promises.writeFile(output, JSON.stringify(manifest) + '\n', {flag:'wx', mode:0o600});
  console.log('Update manifest written');
}
main().catch(error => { console.error(error instanceof Error ? error.message : 'Manifest creation failed'); process.exitCode=1; });
