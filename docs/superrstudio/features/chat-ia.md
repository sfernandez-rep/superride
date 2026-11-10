# Chat IA

Status 2026-11-10: **complete for the next preview (experimental, SuperR
Desktop).** It uses Gemini through the Gemini API, with the user's own Google
AI Studio key. The user chooses the context: general chat, the current file,
or read-only access to the open project. Gemini can propose edits, which the
user reviews and applies in the editor. The Codex and Antigravity agents stay
closed.

- Release text: [CHAT-IA-PREVIEW-NOTES.md](../release/CHAT-IA-PREVIEW-NOTES.md).
- Merging and checks: [chat-ia-integration.md](chat-ia-integration.md).
- Limits: the end of the phase 3 section.

The sections below record, in order, the investigation and each phase. The
early ones describe the agent components as they were then.

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
The staged workspace can now compare explicitly included changed files with
their snapshot and flag changes to the project copy. Review aborts when staged
files are missing, invalid or linked. Creation, deletion, dirty editor buffers,
and application of previews are not implemented; the path checks are not an
OS-enforced security boundary.

The experimental conversation store writes individual bounded JSON records in
an app-owned directory, grouped by the project and provider recorded in each
record. It contains message text in plaintext, can include sensitive content,
and is not connected to the UI. Opening the store defaults to disabled and
requires an explicit enabled argument. This is a backend guard, not an informed
consent interface. Revision checks reject stale concurrent saves; provide a
clear opt-in and deletion UI before exposing history.

## Official provider constraints

Google documents `agy acp` as ACP over stdin/stdout, `oauth-personal`, and the
`--sandbox` and `--disable-telemetry` flags. However, its documented CLI defaults
can permit workspace writes without prompting, and inherited user rules may
preapprove other actions. A session directory or a declined ACP request is not
a sandbox. Require and verify an isolated, fail-closed policy before enabling
the provider; do not modify a user's global permissions or copy Google tokens.
Sources: [ACP setup](https://antigravity.google/docs/ide/extensions/acp/) and
[permissions](https://antigravity.google/docs/permissions?tab=cli).
The documented CLI sandbox is for terminal commands and can be unavailable on
unsupported Windows builds; it does not establish confinement for the ACP
agent itself. Microsoft's experimental
[Create Process in Sandbox](https://learn.microsoft.com/en-us/windows/win32/secauthz/createprocessinsandbox)
API is not a drop-in replacement for the existing stdio transport: its
`inheritHandles` parameter must currently be false. A separate, tested IPC and
process-lifecycle design is needed before relying on it.
Antigravity's [plan mode](https://antigravity.google/docs/cli/modes) adds a
planning instruction; it must not be treated as an OS access-control boundary.

### Personal Google accounts in a third-party application (checked 2026-11-10)

Google's pages disagree, and the stricter ones govern consumer accounts:

- The [ACP guide](https://antigravity.google/docs/ide/extensions/acp/) says
  "Any ACP client can launch Antigravity CLI" and documents `oauth-personal`
  ("Log in with Google"). The [FAQ](https://antigravity.google/docs/faq/) says
  personal `@gmail.com` accounts can use Antigravity on the free tier.
- The [terms](https://antigravity.google/terms), section 6: "Using third party
  software, tools, or services to access the Service (e.g. using OpenClaw with
  Antigravity OAuth) is a breach of this Agreement. Such actions may be grounds
  for suspension or termination of your Antigravity and/or Gemini CLI accounts."
- The FAQ: "Wrapping `agy` inside third-party coding agents or applications ...
  is not supported under consumer plans", and "To use a third-party coding
  agent with Gemini, we recommend using a Gemini Enterprise or Google AI Studio
  API key."

SuperR is a third-party application that would launch `agy`. Therefore
**SuperR does not offer the personal Google sign-in** (`oauth-personal`): the
bridge refuses it and the panel says why. It was not attempted, and no Google
credential was created, read or used. The documented alternative is the
`gemini-api-key` ACP method with the owner's own Google AI Studio API key
(`GEMINI_API_KEY` in the agent's environment). It is not implemented and needs
the owner's decision: AI Studio's free tier has its own terms and data use, and
the key needs protected storage (the existing credential vault).

OpenAI documents its separate [Sign in with ChatGPT flow](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
including dynamic registration, PKCE, ID-token verification, granted scopes,
protected per-account storage and refresh. [Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)
receives this application's own granted access token, not another client's login.
OpenAI currently identifies eligible Plus and Pro accounts for this flow; no
Free entitlement is claimed. Its [example devkit](https://github.com/openai/sign-in-with-chatgpt-devkit/blob/main/LICENSE)
is under a noncommercial license: do not copy or vendor that code into this
AGPL project without a separate license review. Implement against the documented
protocol independently or find a compatible implementation.


## Gemini API mode (owner decision 2026-11-10)

The owner chose Gemini through their own free Google AI Studio API key, called
directly. It does not use Antigravity, so Antigravity's consumer-login
restriction and its tool-isolation problem do not apply. The ACP adapter is kept,
unchanged and closed.

- `superr-agent/gemini-api.ts` calls the REST API
  (`streamGenerateContent?alt=sse` and `models`). It sends only the typed
  conversation, held in memory and dropped on *New conversation*, on removing
  the key, or on quit. There are no tools, project files or system prompt. The
  key goes in the `x-goog-api-key` header, never in a URL. Requests use
  Electron `net.fetch`, so they follow the system proxy.
- The key is checked with `models.list` before it is saved. It is stored with
  the existing `CredentialVault` (new `saveSecret`/`loadSecret`) under
  `userData/superr-chat/gemini-api`, encrypted by Electron `safeStorage`
  (Windows DPAPI). It never goes back to the renderer.
- The model must be one of the text models that Google's pricing page lists
  with a free tier (2026-11-10): `gemini-3.6-flash`, `gemini-3.8-flash`,
  `gemini-3.5-flash-lite` and `gemini-3.1-flash-lite`. The panel offers only
  those that the key's `models.list` shows; the bridge refuses any other model.
  This keeps paid-only models out, but whether a request is billed depends on the
  key's project. SuperR never asks for a card or links billing, and the panel
  tells the user to create the key in a project without billing.
- Errors are mapped from Google's `google.rpc.Status` body (format checked with
  a made-up key) to messages for:
  - an invalid key;
  - quota or rate limit (429);
  - free-tier verification;
  - permission;
  - prepaid billing;
  - region;
  - model;
  - safety block;
  - overload (5xx);
  - connection failure.
- The panel's privacy notice repeats Google's terms for unpaid services: content
  may be used to improve Google products, human reviewers may read it, and
  users should not send sensitive data.
- Further terms the owner should know:
  - Gemini API terms: users must be 18 or older;
  - the API is "for developers building with Google AI models for professional
    or business purposes, not for consumer use";
  - only paid services may be offered to users in the EEA, Switzerland or the
    UK.

  Reconsider these before distributing this mode beyond the owner's own use.

Evidence (2026-11-10):

- *Simulated:* 35 component tests, including `agent-gemini-api.test.cjs` with a
  fake `fetch`. They cover:
  - fragmented SSE, skipped thoughts, the header, and the key never in the URL;
  - model filtering and paging;
  - every error kind, errors inside the stream and blocked prompts;
  - cancel, the busy check, history alternation and *New conversation*;
  - encrypted storage, with no key in the file.
- *Real:* `test-gui-scatter.ps1 -Scenario chat` in a fresh desktop profile.
  A made-up key typed into the panel was rejected by Google itself
  (`API_KEY_INVALID`), and the panel showed "The API key is not valid…". After
  quit, the key was found nowhere in the profile, logs included.
- *Not yet run:* a conversation with a real key. The owner enters the key;
  then run `test-gui-scatter.ps1 -Scenario chat-real` (profile
  `gui-chat-real`).

## Panel redesign (phase 1, 2026-11-10)

The owner's first real conversation through the panel worked (Gemini 3.6
Flash). Phase 1 rebuilt the panel's interface on the same bridge.

- **Layout.** A compact two-row header: title, state, *New conversation*,
  *Manage connection* and close on the first row; provider and model on the
  second. The key setup is a collapsible section, shown when no key is saved
  or on demand ("Change key"). Below the header is a notice line, then the
  conversation, then a composer that grows with its text. Reflow happens on
  resize, and wide and narrow sidebars are tested.
- **Real states.** The panel shows: not configured, checking, connected,
  generating, error, quota exhausted, offline, or unavailable (agents). A saved
  key shows "Gemini connected" only after Google accepts it again
  (`models.list`, which costs no generation quota). Network failures and
  overload show as offline, and an invalid saved key as an error. Codex and
  Antigravity show their own states.
- **Markdown.** `ChatMarkdown.java` builds DOM nodes from text nodes only, never
  innerHTML, so HTML in an answer stays text. It supports headings, bold,
  italic, inline and fenced code, nested and ordered lists, tables, quotes and
  rules. Links open externally and only for http, https or mailto. Code blocks
  show the language, R highlighting, and *Copy* and *Insert in editor*. Insert
  goes through the active editor's `insertCode`, so Ctrl+Z undoes it. During
  streaming only the current answer is re-rendered, at most every 60 ms.
- **Composer.** Enter sends and Shift+Enter adds a new line (IME composition is
  respected). Send is disabled when empty, busy or not connected. *Stop*
  replaces *Send* only while an answer is generated. The draft survives closing
  and reopening the panel.
- **Models and quota.** The free-tier list is kept, filtered by the key's
  `models.list`. The choice is remembered (desktop local storage) and a
  vanished model is reported, never silently replaced. A 429 shows only what
  Google returned (`QuotaFailure` scope and `quotaValue`, `RetryInfo` delay).
  *View my project's limits* opens Google AI Studio's own rate-limit page. No
  counters are estimated.
- **New conversation** cancels a running answer (it ends as cancelled and is not
  kept in history), clears the view and history, and keeps the key, provider
  and state.
- **Tests.** `test-gui-scatter.ps1 -Scenario chat-ui` drives the real desktop
  against `tests/superrstudio/fixtures/fake-gemini.cjs`, a **simulated** Gemini
  API that uses no quota. The desktop accepts `SUPER_RSTUDIO_GEMINI_TEST_BASE`
  only as `http://127.0.0.1:<port>/v1beta`. The test covers states, Markdown,
  copy, insert and undo, Stop, New conversation, a 429, a retired model, the
  draft, and light, dark, wide and narrow screenshots. `-Scenario chat-real`
  (one real request with the owner's key) passed: the answer rendered with 5
  code blocks and no literal Markdown markers.

## Project context (phase 2, 2026-11-10)

Gemini can now see what the user authorises, chosen per message under the
conversation:

- *General chat*: only the typed text.
- *Current file*: the active editor document, with unsaved changes and the
  selection, attached to the message (one request).
- *Project*: read-only access to the open RStudio project.

SuperR decides what is read. The model has no file-system access of its own.

- `superr-agent/project-context.ts` is provider-neutral. The renderer sends what
  the IDE shows: the project folder, the active document with unsaved text and
  selection, and other open documents with unsaved changes. The main process
  expands the IDE's `~/...` paths, then validates. A project root must be a
  real directory with an `.Rproj` file. It may not be a drive root, the OS home
  folder, RStudio's `~` (Documents), or any folder that contains them; this also
  holds across drives.
- Files are read only through `ProjectReader`:
  - allowed extensions only; names that look like secrets (`.env`,
    `.Renviron`, `*credential*`, `*secret*`, keys) are excluded, and so are
    `.git`, `renv`, `node_modules` and build output;
  - links and junctions are rejected anywhere in the path, and paths are
    canonical and must stay inside the project;
  - size limits: 60 000 characters per file and 180 000 per call; data files
    over 32 KB are read only from the start (new `readHead`);
  - `.rds` and `.RData` are reported with their size and never read.
- Unsaved editor text takes priority over the disk.
- In project mode the system instruction carries a file index: names, sizes,
  binary and unsaved flags, never content. The functions are
  `get_project_context` (packages from `library`/`require`/`pkg::`),
  `list_project_files`, `read_project_files` (up to 8 per call),
  `search_project_files`, `get_active_document` and `get_selected_code`; the last
  two refuse documents outside the project. Function rounds are limited to 4 per
  message, and each costs one request of the user's quota. The instruction asks
  the model to batch reads and never to claim it read files it did not receive.
- The Gemini client keeps the model's parts as received (thought signatures)
  for the next request, as Gemini 3 function calling requires.
- The panel shows the context of each message and what was disclosed: "Sent to
  Google: file (unsaved)", "Read: …". A privacy notice appears when a file or
  project mode is chosen.
- *Editor actions* (explain selection, explain file, review code, send
  selection to the chat) use the active editor; the first three switch to
  *Current file*. No new IDE commands were added, so upstream files stay
  untouched.
- **Evidence.**
  - 47 component tests on real temporary projects (simulated Gemini). They
    cover: roots (relative, drive root, home folder, ancestor of a home, no
    `.Rproj`, empty project), traversal, junction, `.env`, `secrets.R`, absolute
    paths, a large CSV, `.rds`, Unicode names, the unsaved buffer, the 8-path
    limit, packages, search, the function loop with the signature, a quota
    error during a read (files already read are reported) and the round limit.
  - `-Scenario chat-project` runs the real desktop on a fixture project against
    the simulated model, and passed.
  - `-Scenario chat-real-project` sent one **real** question with the owner's
    key. Gemini 3.6 Flash read `R/01-cargar.R`, `R/02-graficos.R` and
    `análisis_ñandú.R`, explained each script and how they link (TropFishR
    `lfqCreate`, `source()`, the ggplot2 histogram), and said it had not read the
    data files.

## Reviewed edits (phase 3, 2026-11-10)

Gemini can propose changes to scripts. SuperR shows them as diffs, and only the
user applies them, in the editor.

- `propose_file_edit` is offered in current-file mode (the attached document
  only) and project mode (`.R`, `.Rmd` and `.qmd` inside the project). Its
  arguments are a path, a one-line summary, and exact-text edits; each
  `old_text` must occur exactly once in the current text.
- `superr-agent/edit-proposal.ts` checks the edits:
  - it applies them with the existing `previewTextEdit`, which refuses
    overlaps and split surrogate pairs;
  - it matches a CRLF document in CRLF;
  - it computes an LCS line diff in hunks with 3 lines of context.

  The base is the unsaved editor text, else the active document, else the file
  on disk, read through `ProjectReader` with the same path rules as reads.
  Nothing is written. The model is told the proposal has *not* been applied.
  At most 10 proposals per message.
- Proposals reach the panel as events and again in the turn's reply; the
  panel shows each id once. `ChatEditReview.java` shows a card per proposal:
  file, +/− counts, summary, diff, and *Accept* / *Reject*. A turn with
  several proposals also gets *Accept all*.
- **Accepting** opens or finds the document in the editor (`openFile`,
  `ensureTextEditorActive`) and checks it still equals the proposal's base. If
  not, the proposal is marked stale and nothing changes. With several
  proposals, every document is checked before any is changed (all or nothing),
  and a failure restores those already changed. The replacement is one
  `replaceRange` on the document, so it can be undone with Ctrl+Z. The document
  stays unsaved; RStudio's save keeps its encoding and line-ending settings.
- **Revert** restores the original while the document still equals the applied
  text; otherwise it points to Ctrl+Z.
- Nothing runs commands, installs packages or writes files.
- **Evidence.**
  - Unit tests:
    - exact-match counts, overlaps, CRLF and Unicode;
    - hunks and merging, and a line-ending-only change with no hunks;
    - proposals from the unsaved buffer or the disk;
    - refusals for outside paths, a junction, data files and secret-looking
      names;
    - file-mode limits, and the bridge publishing a proposal while the file
      stays unwritten.
  - `-Scenario chat-edit` runs the real desktop with the simulated model. It
    covers: reject; accept (unsaved, undo and redo); Revert; an unsaved base; a
    stale proposal after an editor change; a stale proposal after a disk
    change; two files all or nothing; a path outside the project refused; and
    current-file mode. No file on disk was written.
  - `-Scenario chat-real-edit` was **real**, with the owner's key. Asked to
    fix `R/03-errores.R` (an unclosed `mean(` and `binwdth`), Gemini 3.6 Flash
    read the scripts and proposed one change (+15 −3): both fixes, plus a
    clearer histogram with `geom_vline` at the mean, labels and
    `theme_minimal()`. Accepted in the editor, the result passed `parse()` in R,
    and the file on disk was unchanged.

### Consolidation before integration (2026-11-10)

Three findings from the final validation:

- **Final text in the reply.** Electron does not order a `webContents.send`
  event against the reply of an `ipcMain.handle`. The last streamed fragments
  could therefore arrive after the turn had ended, which showed "(Gemini
  returned no text)" and could cut off an answer's end. The reply now carries
  the whole answer as well as the turn's proposals (`text`, `proposals`). The
  panel keeps the more complete text and shows each proposal once.
- **No window access at construction.** The Chat IA IPC no longer touches
  `mainWindow.window` when `GwtCallback` is constructed. Cleanup happens on
  `app` `will-quit`. The upstream `DesktopCallback` unit test constructs
  `GwtCallback` with a stub that has no window, and failed before this change.
- **New checks.** The `disabled` desktop scenario now checks that Chat IA's
  button is absent and its IPC refused. `chat-edit` now saves an accepted
  change and checks that the file on disk equals the accepted text.
- **Line endings on save.** The save check found that a file written with LF is
  saved with CRLF on Windows. This is RStudio's own save: its "Line ending
  format" preference (`line_ending_conversion`, default `native`) applies to
  every save. The test confirmed that a manual edit of another LF file, saved
  the same way, is converted too. Chat IA applies its text with the document's
  own line endings and does not save; to keep a file's endings, choose
  *Passthrough* in Tools › Global Options › Code › Saving.

### Remaining work and limits

- Desktop only. The renderer's `window.desktop` bridge exists only in SuperR
  Desktop, and the panel needs experimental mode.
- **Quota.** Each function round is one request. With the owner's free tier
  (5 per minute and 20 per day for Gemini 3.6 Flash, project-specific),
  analyses with several rounds use the daily quota quickly.
- **Larger projects.** Only the first 300 files are listed in the index.
  Larger projects rely on `list_project_files` or `search_project_files`, and
  no summaries are built.
- **Editor commands.** The editor actions live in the panel. No IDE commands or
  context-menu items were added, which keeps upstream files untouched; adding
  them needs `Commands.cmd.xml`.
- **Binary R data** (`.rds`, `.RData`) is never read.
- **Line endings on save.** Saving follows RStudio's line-ending preference
  (default `native`: CRLF on Windows), as for any edit. A safe summary (for
  example `str()` run by the user) is not automated.
- **History.** It stays in memory only. Persistent history (the experimental
  conversation store) still needs a consent and deletion UI.
- **New and deleted files.** A proposal can only change existing scripts.
- **Codex and Antigravity** stay closed until agent isolation is verified.

## Evidence

- 2026-11-10, **real desktop IPC** (not simulated): the panel
  (`ChatAiPane`) calls four preload functions (`superrChatStatus`,
  `SignIn`, `Send`, `Cancel`) that reach `ipcMain` handlers in
  `gwt-callback.ts`. Only the main workbench frame, with
  `SUPER_RSTUDIO_EXPERIMENTAL=1`, may call them. They delegate to
  `superr-agent/chat-bridge.ts`, which validates the provider and the message
  and fails closed. It starts no agent: a message is refused ("read-only
  isolation not verified"), Stop reports no active turn, and Google sign-in
  is refused (above). `test-gui-scatter.ps1 -Scenario chat`
  (`tests/superrstudio/desktop-chat.cjs`) passed against the rebuilt
  Electron bundle and GWT draft in an isolated profile. Codex's ChatGPT
  sign-in path is wired to the existing account coordinator, but no real
  sign-in was performed. The 28 agent component tests (including
  `agent-chat-bridge.test.cjs`, which uses synthetic accounts) and the
  strict and desktop TypeScript checks pass.

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
- On this continuation, `dev-build.ps1 -Component all` passed the incremental
  Windows native and GWT builds. It did not rebuild Electron or integrate these
  agent components into the running application.
- `test-gui-scatter.ps1 -Scenario ggplot2` passed against the existing Windows
  desktop in an isolated profile. It is not a Chat IA UI or provider test.
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

## Next work (after the preview)

- The limits listed at the end of the phase 3 section.
- Agent providers (Codex, Antigravity) only after verified isolation: inherited
  permissions, sensitive files, outside paths, child processes, cancellation and
  cleanup on Windows and Linux. Codex also needs the SIWC account UI, expiry
  scheduling and stale-lock recovery.
- Persistent per-project history, which needs a consent and deletion UI.
