# SuperR Updater — development status

The experimental Help menu can check GitHub releases for Stable or Preview and
offer the official releases page. General preferences expose a SuperR update
channel and an opt-in automatic check, stored in the SuperR Electron profile.
An automatic check reports a newer release in a non-modal warning bar; it does
not close the IDE. No installer is executed. The existing upstream Posit update
service is not used by this SuperR action. Network checks transmit no project
files. Full desktop validation is still pending until the isolated build passes.

The updater modules include a bounded release check, semantic-version ordering,
Ed25519 manifest verification and a streaming download that checks signed size
and SHA-256. These are not connected to a production update download. The trusted
key set is empty, so production signature verification fails closed. A SHA-256
file published beside an installer is not proof of authenticity.

## Signing preparation

The manual release workflow can optionally prepare a manifest only for a
matching `superr-v<version>` tag after approval in the `superr-release`
environment. Configure tag protection and the environment's reviewers before
setting `SUPERR_UPDATE_SIGNING_KEY` and the matching `SUPERR_UPDATE_KEY_ID` in
that protected environment. The secret
is an Ed25519 PKCS#8 PEM private key. The job writes it to the runner's temporary
directory, removes that file on exit, and uploads the manifest and raw signature
as a separate workflow artifact; it does not publish or attach a release.

Before production use, securely provision and independently verify the matching
public key in `manifest.cjs`, agree on key identifiers and rotation/revocation,
and integrate the signed manifest into a protected release process. Manifests
currently expire 30 days after issuance; a protected re-signing process is
needed to make old releases usable beyond that window. Test recovery and
upgrade in an isolated installation before enabling installer execution.

For offline preparation, set `SUPERR_UPDATE_KEY_ID`; then `create-update-manifest.cjs <version> <installer>
<output>` writes the manifest, and `sign-update-manifest.cjs <manifest>
<signature>` signs it using the external file named by
`SUPERR_UPDATE_SIGNING_KEY_FILE`. These tools refuse to overwrite output; the
signing key must live outside the worktree. Do not commit keys, installers,
downloaded data or credentials.

## Validation

Run `node --test tests/superrstudio/updater-releases.test.cjs
tests/superrstudio/updater-manifest.test.cjs`. The tests use synthetic keys and
fake downloads; they do not validate a real publisher or install an update.
The existing NSIS script supports user and machine modes and runs an old
uninstaller during upgrade. Its behaviour, preservation of profiles, recovery,
UAC and restart must be verified using two isolated installations before any
automatic upgrade is offered. Authenticode and SmartScreen remain separate from
the update-manifest signature.
