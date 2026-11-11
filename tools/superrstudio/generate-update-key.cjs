// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
// Explicit operator action: create an Ed25519 pair outside the repository.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

try {
  const directory = process.argv[2];
  if (!directory || process.argv.length !== 3 || !path.isAbsolute(directory)) throw new Error('Specify an absolute existing directory');
  const workspace = fs.realpathSync(path.resolve(__dirname, '../..'));
  const target = fs.realpathSync(directory);
  const rel = path.relative(workspace, target);
  if (!rel || (!rel.startsWith('..' + path.sep) && rel !== '..' && !path.isAbsolute(rel)))
    throw new Error('Key directory must be outside the repository');
  if (!fs.statSync(target).isDirectory()) throw new Error('Key target must be a directory');
  const privatePath=path.join(target,'superr-update-private.pem');
  const publicPath=path.join(target,'superr-update-public.pem');
  const pair=crypto.generateKeyPairSync('ed25519');
  let privateCreated=false;
  try {
    fs.writeFileSync(privatePath,pair.privateKey.export({format:'pem',type:'pkcs8'}),{flag:'wx',mode:0o600});
    privateCreated=true;
    fs.writeFileSync(publicPath,pair.publicKey.export({format:'pem',type:'spki'}),{flag:'wx',mode:0o644});
  } catch (error) {
    if (privateCreated) fs.unlinkSync(privatePath);
    throw error;
  }
  console.log('Key pair created outside the repository. Protect the private key using OS access controls.');
} catch (error) {
  console.error(error instanceof Error ? error.message : 'Key generation failed');
  process.exitCode=1;
}
