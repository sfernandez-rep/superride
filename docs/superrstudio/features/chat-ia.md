# Chat IA: implementation checkpoint

Status 2026-11-09: **under development, not available in the IDE**. Do not
advertise a working Chat IA, sign-in, editor integration, or safe agent file
access until the remaining work and real-provider acceptance pass.

## Architecture and source evidence

The workbench is GWT/Java (`PaneManager`, `ChatPane`, `SourceColumnManager`),
the native session is C++/R, and Desktop is Electron/TypeScript. Existing
`ChatPane` uses a themed iframe and is coupled to the separately installed Posit
Assistant backend. `PaneManager` already supports a resizable sidebar; the
source editor exposes selection, dirty-state and undoable `replaceRange` APIs.
The C++ `ProcessSupervisor` supports child stdin/stdout and shutdown. Its Posit
chat transport uses Content-Length frames, whereas ACP and Codex app-server use
newline-delimited messages. Reuse these primitives where they fit; do not replace
the existing Posit chat or implement a parallel code editor.

Under `src/node/desktop/src/main/superr-agent/` are experimental, **unwired**
components: bounded JSON-RPC process transport; an Antigravity ACP v1 adapter;
a Codex app-server adapter using an explicitly supplied OAuth token; a bounded
selective UTF-8 project reader; an explicitly populated disposable workspace;
private Antigravity configuration; a provider-neutral turn interface; a local
conversation store; and pure text-proposal validation. Both agents'
simulated requests for writes and command execution currently default to deny.
The independent SIWC OAuth code starts a loopback listener only on request,
validates state, performs PKCE exchange, checks OpenAI's discovery/JWKS origin,
verifies RS256 identity signatures and claims, and checks the granted scope.
Separate credential-vault code supports atomic encrypted records using Electron
`safeStorage` and refuses Linux's plaintext/unknown backend. Refresh and sign-out
helpers serialize updates with a per-profile lock file and retain credentials
if revocation fails unless the caller explicitly elects to clear them. A crash
may leave a lock file; automatic stale-lock recovery is not implemented. These
components are unwired. An account coordinator persists the opaque host ID and
issued client IDs, stores verified identities and credentials, rotates on demand,
and exposes token-free status. Account-selection UI, proactive expiry scheduling,
and integration remain. OAuth and provider requests have
only been exercised with synthetic identity keys and fake endpoints.
The process adapters do not yet provide an independently enforced security
boundary, a working approval interface, protected history, user-facing authentication, or
process-tree cleanup. They must not be exposed to an end user as a complete chat.

The reader lists allowed names and searches locally, rejects common sensitive
paths, symlinks, binaries and files over 1 MiB, and identifies `.rds`/`.RData`
without deserializing them. Staging copies only explicitly selected files before
launch. It does not cover every possible secret and does not provide race-free
OS-level confinement. A running agent can access files through its own tools,
independently of this reader. The proposal helper does not write files: its
preview and conflict checks must be integrated into the existing editor in one
undoable transaction, with explicit approval and correct encoding preservation.

The experimental conversation store writes individual bounded JSON records in
an app-owned directory, grouped by the project and provider recorded in each
record. It contains message text in plaintext, can include sensitive content,
and is not connected to the UI. It does not yet detect stale concurrent saves;
resolve these privacy and concurrency limitations before exposing history.

## Official provider constraints

Google documents `agy acp` as ACP over stdin/stdout, `oauth-personal`, and the
`--sandbox` and `--disable-telemetry` flags. However, its documented CLI defaults
can permit workspace writes without prompting, and inherited user rules may
preapprove other actions. A session directory or a declined ACP request is not
a sandbox. Require and verify an isolated, fail-closed policy before enabling
the provider; do not modify a user's global permissions or copy Google tokens.
Sources: [ACP setup](https://antigravity.google/docs/ide/extensions/acp/) and
[permissions](https://antigravity.google/docs/permissions?tab=cli).

OpenAI documents its separate [Sign in with ChatGPT flow](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
including dynamic registration, PKCE, ID-token verification, granted scopes,
protected per-account storage and refresh. [Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)
receives this application's own granted access token, not another client's login.
OpenAI currently identifies eligible Plus and Pro accounts for this flow; no
Free entitlement is claimed. Its [example devkit](https://github.com/openai/sign-in-with-chatgpt-devkit/blob/main/LICENSE)
is under a noncommercial license: do not copy or vendor that code into this
AGPL project without a separate license review. Implement against the documented
protocol independently or find a compatible implementation.

## Evidence

- Simulated ACP and Codex child processes: handshake, streaming, cancellation,
  denied permission, malformed message and shutdown tests pass.
- Real installed Codex `0.164.0-alpha.11.1`: app-server initialize succeeded
  with a disposable `CODEX_HOME` and dummy token. No login, prompt, inference or
  access to the user's Codex credentials was tested.
- Official Google-signed Antigravity CLI `1.5.3`, downloaded to the local cache
  and checked against the SHA-512 manifest, successfully answered ACP initialize
  with an isolated managed profile and announced `oauth-personal`. Policy
  enforcement during an authenticated agent turn is untested. No Google sign-in,
  prompt, project data or real inference was tested.
- Project-reader tests cover UTF-8/CRLF, traversal, secrets by common names,
  junctions and size limits. In-memory proposal tests cover approval, dirty and
  changed editors, overlap and Unicode. No actual editor was changed.
- OAuth/identity, refresh/revocation and encrypted storage tests pass with
  synthetic data; no real account or authorization grant was used. Windows
  Electron `safeStorage` also encrypted and decrypted a synthetic credential.
- The component tests pass on Ubuntu 24.04 under WSL with a SHA-256-verified
  Node 22.22.2 binary. This is not a Linux build or desktop GUI test.
- TypeScript strict check passes for these new files. Full Windows Desktop build,
  GUI tests, Linux compilation and real Gemini/Codex conversations not yet run.

Re-run the mock tests on this provisioned Windows host:

```powershell
Push-Location tests/superrstudio/agent-test-deps
npm ci --ignore-scripts --no-audit --no-fund
Pop-Location
$env:NODE_PATH = "$PWD\tests\superrstudio\agent-test-deps\node_modules"
$env:TS_NODE_PROJECT = "$PWD\src\node\desktop\tsconfig.json"
$env:TS_NODE_TRANSPILE_ONLY = '1'
& D:\Git\rstudio-tools\dependencies\common\node\22.22.2\node.exe --test --require ts-node/register tests\superrstudio\agent-transport.test.cjs tests\superrstudio\agent-project-reader.test.cjs tests\superrstudio\agent-text-proposal.test.cjs tests\superrstudio\agent-oidc.test.cjs tests\superrstudio\agent-chatgpt-auth.test.cjs tests\superrstudio\agent-vault.test.cjs tests\superrstudio\agent-registration.test.cjs tests\superrstudio\agent-accounts.test.cjs tests\superrstudio\agent-staged-workspace.test.cjs tests\superrstudio\agent-antigravity-policy.test.cjs
```

## Next work

Establish verified agent isolation including inherited permissions, sensitive
files, outside paths, child processes, cancellation and cleanup on Windows and
Linux. Complete SIWC account-selection UI, expiry scheduling, stale-lock
recovery and OS-protected storage integration. Connect a provider-neutral session/approval coordinator to
the actual sidebar, project context and source editor; show diffs, preserve dirty
buffers and provide undo. Persist per-project/provider histories locally without
credentials. Add real GUI and provider tests only with explicit user sign-in.
The owner's full task also requires settings, Markdown, model selection, history,
file activity, context actions, and the complete end-to-end flow.
