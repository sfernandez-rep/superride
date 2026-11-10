// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
// Sign exact manifest bytes. The private key must be an external Ed25519 PEM.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

try {
  const [manifest, signature] = process.argv.slice(2);
  const keyFile = process.env.SUPERR_UPDATE_SIGNING_KEY_FILE;
  if (!manifest || !signature || !keyFile || process.argv.length !== 4) throw new Error('Expected manifest, signature and SUPERR_UPDATE_SIGNING_KEY_FILE');
  const workspace = fs.realpathSync(path.resolve(__dirname, '../..'));
  const keyPath = fs.realpathSync(keyFile);
  const relative = path.relative(workspace, keyPath);
  if (!relative || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative)))
    throw new Error('Signing key must be outside the repository');
  const bytes = fs.readFileSync(manifest);
  if (!bytes.length || bytes.length > 16384) throw new Error('Invalid manifest size');
  const key = crypto.createPrivateKey(fs.readFileSync(keyPath));
  if (key.asymmetricKeyType !== 'ed25519') throw new Error('Expected an Ed25519 private key');
  fs.writeFileSync(signature, crypto.sign(null, bytes, key), {flag:'wx', mode:0o600});
  console.log('Manifest signature written');
} catch (error) {
  console.error(error instanceof Error ? error.message : 'Signing failed');
  process.exitCode = 1;
}
