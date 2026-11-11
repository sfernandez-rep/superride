const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { CredentialVault } = require('../../src/node/desktop/src/main/superr-agent/credential-vault');
const { refreshChatGptGrant, signOutChatGpt } = require('../../src/node/desktop/src/main/superr-agent/chatgpt-auth');

test('encrypted profiles are separate, replace atomically and reject malformed paths', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-vault-'));
  const key = crypto.randomBytes(32);
  const codec = {
    encrypt(text) { const iv = crypto.randomBytes(12), cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
      const body = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
      return Buffer.concat([iv, cipher.getAuthTag(), body]); },
    decrypt(bytes) { const cipher = crypto.createDecipheriv('aes-256-gcm', key, bytes.subarray(0, 12));
      cipher.setAuthTag(bytes.subarray(12, 28)); return Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString('utf8'); },
  };
  const grant = { clientId: 'client', hostId: 'host', subject: 'subject', accessToken: 'sensitive-access-token',
    refreshToken: 'sensitive-refresh-token', idToken: 'sensitive-id-token', savedAt: Date.now(), expiresIn: 3600,
    scopes: ['openid', 'chatgpt.tokens.use.direct'], sharing: true };
  const a = 'a'.repeat(32), b = 'b'.repeat(32);
  try {
    const vault = await CredentialVault.open(root, codec);
    await vault.save(a, grant);
    assert.deepEqual(await vault.load(a), grant);
    assert.equal((await fs.readFile(path.join(root, `${a}.bin`))).includes(Buffer.from('sensitive')), false);
    await vault.save(b, { ...grant, subject: 'other' });
    await vault.save(a, { ...grant, accessToken: 'replacement' });
    assert.equal((await vault.load(a)).accessToken, 'replacement');
    assert.equal((await vault.load(b)).subject, 'other');
    let release;
    const pause = new Promise(resolve => { release = resolve; });
    let entered;
    const locked = new Promise(resolve => { entered = resolve; });
    const updating = vault.update(a, async old => { entered(); await pause; return { ...old, accessToken: 'rotated' }; });
    await locked;
    await assert.rejects(vault.update(a, async old => old), /locked/);
    release();
    assert.equal((await updating).accessToken, 'rotated');
    await assert.rejects(vault.update(a, async old => ({ ...old, subject: 'other' })), /identity/);
    const refreshed = await refreshChatGptGrant(vault, a, async (_url, opts) => {
      assert.equal(opts.body.get('refresh_token'), grant.refreshToken);
      assert.equal(opts.body.has('scope'), false);
      return Response.json({ access_token: 'fresh', refresh_token: 'rotated-refresh', token_type: 'Bearer', expires_in: 3600 });
    });
    assert.equal(refreshed.accessToken, 'fresh');
    assert.equal((await vault.load(a)).refreshToken, 'rotated-refresh');
    await assert.rejects(refreshChatGptGrant(vault, a, async () => Response.json({ error: 'invalid_grant' }, { status: 400 })));
    assert.equal((await vault.load(a)).refreshToken, 'rotated-refresh');
    await assert.rejects(vault.load('../escape'));
    await assert.rejects(vault.save(a, { ...grant, scopes: [], sharing: true }));
    await assert.rejects(signOutChatGpt(vault, a, false, async () => { throw Error('offline'); }), /retained/);
    assert.ok(await vault.load(a));
    assert.equal(await signOutChatGpt(vault, a, true, async () => { throw Error('offline'); }), false);
    assert.equal(await vault.load(a), null);
    await fs.writeFile(path.join(root, `${b}.bin`), Buffer.from('corrupted'));
    await assert.rejects(vault.load(b), /decrypt or validate/);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});
