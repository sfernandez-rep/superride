const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {UpdateDownload} = require('../../src/node/desktop/src/main/superr-updater/download.cjs');
const {_verifyWithKeysForTests} = require('../../src/node/desktop/src/main/superr-updater/manifest.cjs');

test('coordinator verifies metadata before download and reports progress', async () => {
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'superr-download-'));
 const {privateKey,publicKey}=crypto.generateKeyPairSync('ed25519');
 const content=Buffer.from('synthetic installer'); const now=Date.now();
 const data={schema:1,keyId:'test',version:'0.2.0-preview.1',channel:'preview',platform:'windows',arch:'x64',
   artifact:'SuperR-0.2.0-preview.1-Windows-x64.exe',size:content.length,
   sha256:crypto.createHash('sha256').update(content).digest('hex'),issued:now-1000,expires:now+60000};
 const bytes=Buffer.from(JSON.stringify(data)), signature=crypto.sign(null,bytes,privateKey);
 const keys={test:publicKey.export({type:'spki',format:'pem'})};
 const verify=(b,s,id,current,channel)=>_verifyWithKeysForTests(b,s,id,current,channel,keys,now);
 const request=async url=>new Response(url.endsWith('update-manifest.json') ? bytes : url.endsWith('update-manifest.sig') ? signature : content);
 try {
   let requested=false;
   const disabled=new UpdateDownload('0.1.0',root,async ()=>{requested=true;});
   await assert.rejects(disabled.start('superr-v0.2.0-preview.1','preview'),/No trusted/);
   assert.equal(requested,false);
   const progress=[];
   const active=new UpdateDownload('0.1.0',root,request,verify);
   const result=await active.start('superr-v0.2.0-preview.1','preview',p=>progress.push(p));
   assert.equal(result.version,data.version);
   assert.deepEqual(await fs.readFile(result.file),content);
   assert.equal(progress.at(-1).received,content.length);
   await assert.rejects(active.start('superr-v0.2.0-preview.1','stable'),/Invalid or expired/);
   const bad=new UpdateDownload('0.1.0',root,async url=>new Response(url.endsWith('.json') ? bytes : Buffer.alloc(64)),verify);
   await assert.rejects(bad.start('superr-v0.2.0-preview.1','preview'),/signature/);
 } finally { await fs.rm(root,{recursive:true,force:true}); }
});

test('coordinator cancels outstanding metadata work', async () => {
 const pending=new UpdateDownload('0.1.0',os.tmpdir(),async (_,options)=>new Promise((_,reject)=>{
   options.signal.addEventListener('abort',()=>reject(new Error('cancelled')),{once:true});
 }),()=>{throw Error('never reached');});
 const result=pending.start('superr-v0.2.0','stable');
 assert.equal(pending.cancel(),true);
 await assert.rejects(result,/cancelled/);
 assert.equal(pending.cancel(),false);
});
