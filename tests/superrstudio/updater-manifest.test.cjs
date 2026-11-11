const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {verifyManifest, verifyArtifact, downloadArtifact, _verifyWithKeysForTests} = require('../../src/node/desktop/src/main/superr-updater/manifest.cjs');
const {publicKey, privateKey} = crypto.generateKeyPairSync('ed25519');
const keys = {test: publicKey.export({type:'spki', format:'pem'})};
const now = Date.now();
const payload = Buffer.from('test installer');
const item = {schema:1, keyId:'test', version:'0.2.0-preview.1', channel:'preview', platform:'windows', arch:'x64',
 artifact:'SuperR-0.2.0-preview.1-Windows-x64.exe', size:payload.length,
 sha256:crypto.createHash('sha256').update(payload).digest('hex'), issued:now-1000, expires:now+10000};
function signed(value = item) { const bytes=Buffer.from(JSON.stringify(value)); return [bytes, crypto.sign(null,bytes,privateKey)]; }
const verify = (value, current='0.1.0', channel='preview') => {
 const [bytes, sig] = signed(value); return _verifyWithKeysForTests(bytes,sig,'test',current,channel,keys,now);
};

test('trusted signature, channel, expiration and downgrade rules are enforced', () => {
 const [bytes,sig]=signed();
 assert.throws(() => verifyManifest(bytes,sig,'test','0.1.0','preview'), /Untrusted/);
 assert.equal(verify(item).version, item.version);
 assert.throws(() => _verifyWithKeysForTests(bytes,Buffer.alloc(64),'test','0.1.0','preview',keys,now), /signature/);
 assert.throws(() => verify(item,'0.2.0','preview'), /Invalid/);
 assert.throws(() => verify(item,'0.1.0','stable'), /Invalid/);
 assert.throws(() => verify({...item, expires:now-1}), /expired/);
 assert.throws(() => verify({...item, artifact:'../evil.exe'}), /Invalid/);
});

test('download requires a signed manifest and removes partial or redirected data', async () => {
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'superr-updater-'));
 try {
   const manifest=verify(item);
   const file=await downloadArtifact(manifest, dir, async () => new Response(payload));
   assert.deepEqual(await fs.readFile(file),payload);
   await assert.rejects(downloadArtifact({...manifest},dir,async () => new Response(payload)), /Unverified/);
   await assert.rejects(downloadArtifact(manifest,dir,async () => new Response('partial')), /integrity/);
   await assert.rejects(downloadArtifact(manifest,dir,async () => new Response(null,{status:302,headers:{location:'https://evil.invalid/a'}})), /Untrusted/);
   assert.equal((await fs.readdir(dir)).length, 1);
   const aborted=new AbortController(); aborted.abort();
   await assert.rejects(downloadArtifact(manifest,dir,async (_,opts) => {opts.signal.throwIfAborted();},aborted.signal));
   assert.equal((await fs.readdir(dir)).length, 1);
 } finally { await fs.rm(dir,{recursive:true,force:true}); }
});

test('artifact size and hash must match the verified manifest', async () => {
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'superr-updater-'));
 const file=path.join(dir,'file');
 try {
   await fs.writeFile(file,payload);
   await assert.rejects(verifyArtifact(file,{...verify(item)}), /Unverified/);
   await verifyArtifact(file,verify(item));
   await fs.writeFile(file,Buffer.alloc(payload.length, 1));
   await assert.rejects(verifyArtifact(file,verify(item)), /integrity/);
   await fs.writeFile(file, 'short');
   await assert.rejects(verifyArtifact(file,verify(item)), /Invalid/);
 } finally { await fs.rm(dir,{recursive:true,force:true}); }
});

test('release signing tool signs with an external test key without overwriting', async () => {
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'superr-sign-'));
 try {
   const manifest=path.join(dir,'manifest.json'), key=path.join(dir,'key.pem'), signature=path.join(dir,'manifest.sig');
   await fs.writeFile(manifest,JSON.stringify(item));
   await fs.writeFile(key,privateKey.export({type:'pkcs8',format:'pem'}));
   const script=path.join(__dirname,'../../tools/superrstudio/sign-update-manifest.cjs');
   const run=() => spawnSync(process.execPath,[script,manifest,signature],{env:{...process.env,SUPERR_UPDATE_SIGNING_KEY_FILE:key}});
   assert.equal(run().status,0);
   assert.equal(crypto.verify(null,await fs.readFile(manifest),publicKey,await fs.readFile(signature)),true);
   assert.notEqual(run().status,0);
 } finally { await fs.rm(dir,{recursive:true,force:true}); }
});

test('release manifest binds version, filename, size and artifact hash', async () => {
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'superr-manifest-'));
 try {
   const artifact=path.join(dir,'SuperR-0.2.0-preview.1-Windows-x64.exe');
   const output=path.join(dir,'manifest.json');
   await fs.writeFile(artifact,payload);
   const script=path.join(__dirname,'../../tools/superrstudio/create-update-manifest.cjs');
   const env={...process.env,SUPERR_UPDATE_KEY_ID:'test'};
   const result=spawnSync(process.execPath,[script,'0.2.0-preview.1',artifact,output],{env});
   assert.equal(result.status,0);
   const manifest=JSON.parse(await fs.readFile(output,'utf8'));
   assert.equal(manifest.channel,'preview');
   assert.equal(manifest.size,payload.length);
   assert.equal(manifest.sha256,item.sha256);
   assert.notEqual(spawnSync(process.execPath,[script,'0.2.0',artifact,path.join(dir,'wrong.json')],{env}).status,0);
 } finally { await fs.rm(dir,{recursive:true,force:true}); }
});

test('key generator creates a matching pair only in an external directory', async () => {
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'superr-keys-'));
 try {
   const script=path.join(__dirname,'../../tools/superrstudio/generate-update-key.cjs');
   assert.notEqual(spawnSync(process.execPath,[script,path.resolve(__dirname,'../..')]).status,0);
   assert.equal(spawnSync(process.execPath,[script,dir]).status,0);
   const priv=crypto.createPrivateKey(await fs.readFile(path.join(dir,'superr-update-private.pem')));
   const pub=crypto.createPublicKey(await fs.readFile(path.join(dir,'superr-update-public.pem')));
   assert.equal(crypto.verify(null,payload,pub,crypto.sign(null,payload,priv)),true);
   assert.notEqual(spawnSync(process.execPath,[script,dir]).status,0);
 } finally { await fs.rm(dir,{recursive:true,force:true}); }
});
