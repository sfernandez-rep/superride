const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { RegistrationStore } = require('../../src/node/desktop/src/main/superr-agent/registration-store');

test('host identity is stable and issued registrations remain distinct', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'superr-reg-'));
  try {
    const store = await RegistrationStore.open(root);
    const first = await store.readOrCreate();
    assert.match(first.hostId, /^urn:uuid:/);
    const a = 'a'.repeat(32), b = 'b'.repeat(32);
    await store.remember(a, 'oaiapp_one');
    await store.remember(b, 'oaiapp_two');
    const next = await (await RegistrationStore.open(root)).readOrCreate();
    assert.equal(next.hostId, first.hostId);
    assert.equal(next.registrations[a].clientId, 'oaiapp_one');
    assert.equal(next.registrations[b].clientId, 'oaiapp_two');
    await store.rememberSubject(a, 'c'.repeat(64));
    await assert.rejects(store.rememberSubject(a, 'd'.repeat(64)), /identity/);
    await assert.rejects(store.remember(a, 'oaiapp_other'), /different/);
    await assert.rejects(store.remember('../escape', 'oaiapp_one'), /Invalid/);
    await assert.rejects(store.remember(a, 'dynamic_agent_client'), /Invalid/);
    const metadata = await fs.readFile(path.join(root, 'registrations.json'), 'utf8');
    assert.doesNotMatch(metadata, /accessToken|refreshToken|idToken|email/);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});
