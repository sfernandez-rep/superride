# SuperR Updater — development status

The experimental Help menu can check GitHub releases for Stable or Preview and
offer the official releases page. General preferences expose a SuperR update
channel and an opt-in automatic check, stored in the SuperR Electron profile.
An automatic check reports a newer release in a non-modal warning bar; it does
not close the IDE. No installer is executed. The existing upstream Posit update
service is not used by this SuperR action. Network checks transmit no project
files. The Windows development desktop, native session, Electron and GWT were
built and checked in an isolated worktree/profile. The actual release lookup,
native channel dialog, and update preferences including restart persistence
were exercised; no installed SuperR copy was upgraded.

The desktop can request a download with progress and cancellation; the main
process obtains the manifest and signature from the selected GitHub release,
checks Ed25519, version/channel, signed size and SHA-256 before retaining the
installer. The trusted key set is empty, so production downloads fail before
accessing the network. No installation action is enabled. A SHA-256 file
published beside an installer is not proof of authenticity.

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

Generate a pair only on a trusted machine by creating a restricted directory
**outside the repository** and running `node tools/superrstudio/generate-update-key.cjs
<absolute-directory>`. It writes separate `superr-update-private.pem` and
`superr-update-public.pem` files without printing either key. On Windows the
operator must restrict the directory and private-key ACL: Unix mode `0600`
alone does not enforce Windows ACLs. Keep an offline recovery copy protected;
only the public key belongs in the source. Verify its fingerprint through an
independent trusted channel before the initial trusted build is distributed.

In GitHub Settings, protect the `superr-release` environment with reviewers,
create its secret `SUPERR_UPDATE_SIGNING_KEY` containing the private PEM, and
create its variable `SUPERR_UPDATE_KEY_ID` matching the pinned public key. Protect
release tags separately. The optional signing job produces a workflow artifact;
an authorized publisher must attach both `update-manifest.json` and
`update-manifest.sig` to the appropriate release after review. No job publishes
a release automatically as part of signing.

For planned rotation, ship a new SuperR build containing both old and new public
keys as an update signed by the existing trusted key, wait until supported
clients have that build, then switch the release signing secret and key ID.
Retire the old key only in a later build signed through an already trusted key.
Never add keys merely because a downloaded manifest contains them. If the old
key is compromised or unavailable, use a separately authenticated manual
bootstrap; a compromised key cannot establish a trustworthy rotation chain.

For offline preparation, set `SUPERR_UPDATE_KEY_ID`; then `create-update-manifest.cjs <version> <installer>
<output>` writes the manifest, and `sign-update-manifest.cjs <manifest>
<signature>` signs it using the external file named by
`SUPERR_UPDATE_SIGNING_KEY_FILE`. These tools refuse to overwrite output; the
signing key must live outside the worktree. Do not commit keys, installers,
downloaded data or credentials.

## Validation

Run `node --test tests/superrstudio/updater-releases.test.cjs
tests/superrstudio/updater-manifest.test.cjs tests/superrstudio/updater-download.test.cjs`.
On Windows with NSIS installed, also run `node --test tests/superrstudio/updater-nsis.test.cjs`.
The tests use synthetic keys and
fake downloads; they do not validate a real publisher or install an update.
The existing NSIS script supports user and machine modes and runs an old
uninstaller during upgrade. The direct `ExecWait` path now aborts on a nonzero
exit; a small registry-free NSIS fixture tests the same-mode exit paths. The
legacy elevated `ExecShellWait` fallback does not obtain an exit code and can
still misclassify failure; it needs a safe verification strategy. This is not a
SuperR upgrade test.
The existing product installer uses shared SuperR registry keys and packaging
defaults to `C:\rsbuild`; the current machine has no Windows Sandbox, so no
two-version product installation was attempted. Its behaviour, preservation of
profiles, recovery, UAC and restart must be verified using two genuinely isolated
installations before any automatic upgrade is offered. The packaged Electron
binary disables `RunAsNode`; a future updater helper must not depend on that
fuse being enabled. Authenticode and SmartScreen remain separate from the
update-manifest signature.
