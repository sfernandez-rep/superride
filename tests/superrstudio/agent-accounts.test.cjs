const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { ChatGptAccounts } = require('../../src/node/desktop/src/main/superr-agent/chatgpt-accounts');

test('account coordinator stores the issued registration and exposes no tokens in status', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-accounts-'));
  const key = crypto.randomBytes(32);
  const codec = {
    encrypt(text) { const iv = crypto.randomBytes(12), c = crypto.createCipheriv('aes-256-gcm', key, iv);
      const bytes = Buffer.concat([c.update(text, 'utf8'), c.final()]); return Buffer.concat([iv, c.getAuthTag(), bytes]); },
    decrypt(bytes) { const c = crypto.createDecipheriv('aes-256-gcm', key, bytes.subarray(0, 12));
      c.setAuthTag(bytes.subarray(12, 28)); return Buffer.concat([c.update(bytes.subarray(28)), c.final()]).toString('utf8'); },
  };
  const pair = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = { ...pair.publicKey.export({ format: 'jwk' }), kid: 'k', alg: 'RS256', use: 'sig' };
  const encode = v => Buffer.from(JSON.stringify(v)).toString('base64url');
  let auth, subject = 'subject';
  const mockFetch = async (url, opts) => {
    if (url.endsWith('/oauth/token')) {
      const now = Math.floor(Date.now() / 1000);
      const content = `${encode({alg:'RS256',kid:'k'})}.${encode({iss:'https://auth.openai.com',aud:'oaiapp_test',sub:subject,nonce:auth.searchParams.get('nonce'),iat:now,exp:now+60})}`;
      return Response.json({id_token:`${content}.${crypto.sign('RSA-SHA256',Buffer.from(content),pair.privateKey).toString('base64url')}`,
        access_token:'secret-access',refresh_token:'secret-refresh',token_type:'Bearer',expires_in:3600,scope:'openid chatgpt.tokens.use.direct'});
    }
    if (url.endsWith('/openid-configuration')) return Response.json({issuer:'https://auth.openai.com',jwks_uri:'https://auth.openai.com/jwks',revocation_endpoint:'https://auth.openai.com/revoke'});
    if (url.endsWith('/jwks')) return Response.json({keys:[jwk]});
    if (url.endsWith('/revoke')) { assert.equal(opts.body.get('token'), 'secret-refresh'); return new Response('', {status:200}); }
    throw Error('Unexpected URL');
  };
  const accounts = await ChatGptAccounts.open(root, codec, mockFetch);
  try {
    const flow = await accounts.beginSignIn();
    auth = new URL(flow.authorizeUrl);
    const callback = new URL(auth.searchParams.get('redirect_uri'));
    callback.searchParams.set('state', auth.searchParams.get('state'));
    callback.searchParams.set('code', 'fake-code');
    callback.searchParams.set('client_id', 'oaiapp_test');
    assert.equal((await fetch(callback)).status, 200);
    const account = await flow.result;
    assert.equal(account.sharing, true);
    assert.doesNotMatch(JSON.stringify(account), /secret/);
    assert.doesNotMatch(JSON.stringify(await accounts.list()), /secret/);
    assert.equal(await accounts.accessToken(account.id), 'secret-access');
    assert.equal(await accounts.signOut(account.id), true);
    assert.equal((await accounts.list())[0].state, 'signed_out');
    await assert.rejects(accounts.accessToken(account.id), /not connected/);
    subject = 'different-user';
    const retry = await accounts.beginSignIn(account.id);
    auth = new URL(retry.authorizeUrl);
    const retryCallback = new URL(auth.searchParams.get('redirect_uri'));
    retryCallback.searchParams.set('state', auth.searchParams.get('state'));
    retryCallback.searchParams.set('code', 'fake-code');
    const rejected = assert.rejects(retry.result, /could not be verified/);
    assert.equal((await fetch(retryCallback)).status, 200);
    await rejected;
    assert.equal((await accounts.list())[0].state, 'signed_out');
  } finally { accounts.shutdown(); await fs.rm(root, {recursive:true,force:true}); }
});
