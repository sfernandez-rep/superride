const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { verifyOpenAiIdentity } = require('../../src/node/desktop/src/main/superr-agent/oidc-identity');

test('ID token signature, issuer, audience, expiry and nonce are verified', () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'one', alg: 'RS256', use: 'sig' };
  const header = { alg: 'RS256', kid: 'one' };
  const claims = { iss: 'https://auth.openai.com', aud: 'client-1', sub: 'subject', nonce: 'nonce-1', iat: 100, exp: 200 };
  const encode = v => Buffer.from(JSON.stringify(v)).toString('base64url');
  const sign = (head, payload, key = privateKey) => {
    const content = `${encode(head)}.${encode(payload)}`;
    return `${content}.${crypto.sign('RSA-SHA256', Buffer.from(content), key).toString('base64url')}`;
  };
  const check = (token, keys = { keys: [jwk] }, aud = 'client-1', nonce = 'nonce-1', now = 150) =>
    verifyOpenAiIdentity(token, keys, aud, nonce, now);
  assert.deepEqual(check(sign(header, claims)), { subject: 'subject' });
  assert.throws(() => check(sign(header, claims), undefined, 'wrong'));
  assert.throws(() => check(sign(header, claims), undefined, 'client-1', 'wrong'));
  assert.throws(() => check(sign(header, claims), undefined, 'client-1', 'nonce-1', 201));
  assert.throws(() => check(sign(header, { ...claims, iss: 'https://evil.example' })));
  assert.throws(() => check(sign({ ...header, alg: 'none' }, claims)));
  assert.throws(() => check(sign(header, claims), { keys: [jwk, jwk] }));
  const other = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey;
  assert.throws(() => check(sign(header, claims, other)));
  assert.throws(() => check(sign(header, { ...claims, aud: ['client-1', 'client-2'] })));
});
