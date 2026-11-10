const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {verifyManifest, verifyArtifact} = require('../../src/node/desktop/src/main/superr-updater/manifest.cjs');
const {publicKey, privateKey} = crypto.generateKeyPairSync('ed25519');
const keys = {test: publicKey.export({type:'spki', format:'pem'})};
const now = Date.now();
const payload = Buffer.from('test installer');
const item = {schema:1, version:'0.2.0-preview.1', channel:'preview', platform:'windows', arch:'x64',
 artifact:'SuperR-0.2.0-preview.1-Windows-x64.exe', size:payload.length,
 sha256:crypto.createHash('sha256').update(payload).digest('hex'), issued:now-1000, expires:now+10000};
function signed(value = item) { const bytes=Buffer.from(JSON.stringify(value)); return [bytes, crypto.sign(null,bytes,privateKey)]; }
const verify = (value, current='0.1.0', channel='preview') => {
 const [bytes, sig] = signed(value); return verifyManifest(bytes,sig,'test',current,channel,{trustedKeys:keys,now});
};

test('trusted signature, channel, expiration and downgrade rules are enforced', () => {
 const [bytes,sig]=signed();
 assert.throws(() => verifyManifest(bytes,sig,'test','0.1.0','preview'), /Untrusted/);
 assert.equal(verify(item).version, item.version);
 assert.throws(() => verifyManifest(bytes,Buffer.alloc(64),'test','0.1.0','preview',{trustedKeys:keys,now}), /signature/);
 assert.throws(() => verify(item,'0.2.0','preview'), /Invalid/);
 assert.throws(() => verify(item,'0.1.0','stable'), /Invalid/);
 assert.throws(() => verify({...item, expires:now-1}), /expired/);
 assert.throws(() => verify({...item, artifact:'../evil.exe'}), /Invalid/);
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
