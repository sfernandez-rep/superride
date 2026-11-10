// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const {parseVersion} = require('./releases.cjs');
const {verifyManifest, hasTrustedKeys, downloadArtifact} = require('./manifest.cjs');

/** Fetch a small release asset without accepting redirects to arbitrary hosts. */
async function releaseAsset(version, name, request, signal, limit) {
  let url = `https://github.com/sfernandez-rep/superride/releases/download/superr-v${version}/${name}`;
  let response;
  for (let i=0; i<4; i++) {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port ||
        !['github.com', 'release-assets.githubusercontent.com'].includes(parsed.hostname))
      throw new Error('Untrusted release destination');
    response = await request(url, {redirect:'manual', signal});
    if (![301,302,303,307,308].includes(response.status)) break;
    const location = response.headers.get('location');
    if (!location || i === 3) throw new Error('Invalid release redirect');
    if (response.body) await response.body.cancel();
    url = new URL(location, url).href;
  }
  if (!response || !response.ok || !response.body) throw new Error('Signed update metadata is unavailable');
  const reader = response.body.getReader(); const chunks=[]; let size=0;
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.byteLength;
      if (size > limit) { await reader.cancel(); throw new Error('Signed update metadata is too large'); }
      chunks.push(part.value);
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks);
}

/** Main-process coordinator; caller supplies the current version, never the renderer. */
class UpdateDownload {
  constructor(currentVersion, root, request=fetch, verify=verifyManifest) {
    if (!parseVersion(currentVersion)) throw new Error('Invalid installed version');
    this.currentVersion=currentVersion; this.root=root; this.request=request; this.verify=verify; this.active=null;
  }
  async start(tag, channel, onProgress=()=>{}) {
    if (this.active) throw new Error('An update download is already running');
    if (typeof tag !== 'string' || !tag.startsWith('superr-v') || !parseVersion(tag) ||
        !['stable','preview'].includes(channel)) throw new Error('Invalid release selection');
    if (this.verify === verifyManifest && !hasTrustedKeys()) throw new Error('No trusted update signing key is configured');
    const version=tag.slice('superr-v'.length);
    const controller=new AbortController(); this.active=controller;
    const signal=AbortSignal.any([controller.signal, AbortSignal.timeout(30 * 60 * 1000)]);
    try {
      onProgress({stage:'verifying', received:0, total:0});
      const bytes=await releaseAsset(version,'update-manifest.json',this.request,signal,16384);
      const signature=await releaseAsset(version,'update-manifest.sig',this.request,signal,64);
      let keyId;
      try { keyId=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes)).keyId; }
      catch { throw new Error('Invalid update manifest'); }
      const manifest=this.verify(bytes,signature,keyId,this.currentVersion,channel);
      if (manifest.version !== version) throw new Error('Release and manifest versions do not match');
      let last=0;
      const file=await downloadArtifact(manifest,this.root,this.request,signal,(received,total)=> {
        const now=Date.now();
        if (received===total || now-last>=100) { last=now; onProgress({stage:'downloading',received,total}); }
      });
      return {version:manifest.version, file, manifest};
    } finally { if (this.active===controller) this.active=null; }
  }
  cancel() { if (!this.active) return false; this.active.abort(); return true; }
  shutdown() { this.cancel(); }
}
module.exports={UpdateDownload,releaseAsset};
