# Integrating Chat IA (`feature/chat-ia`)

For whoever merges Chat IA with SuperR Updater (`feature/auto-updater`) into the
next preview. The feature is complete for the preview and verified. The
design, evidence and limits are in [chat-ia.md](chat-ia.md); the user-facing
text is in
[CHAT-IA-PREVIEW-NOTES.md](../release/CHAT-IA-PREVIEW-NOTES.md).

## Branch state

- Branch `feature/chat-ia`, based on `develop` at `0498d1776c` (= `main`).
  The validated code is `272494bfbb`; the commit after it adds only
  documentation. GitHub `SuperR checks` passes on Windows and Ubuntu for
  `272494bfbb`. The state is recorded in [HANDOFF.md](../../../HANDOFF.md)
  ("Chat IA: ready to integrate").
- No change to `main`, `develop`, `feature/auto-updater` or any release.
- No Commands.cmd.xml, user-preference schema, C++ or R change. Everything is
  behind `SUPER_RSTUDIO_EXPERIMENTAL=1`.

## Files

### SuperR files

- `src/node/desktop/src/main/superr-agent/`:
  - `chat-bridge.ts` (provider surface);
  - `gemini-api.ts` (REST client, streaming, function calls, quota details);
  - `project-context.ts` (read-only context and functions);
  - `edit-proposal.ts` (proposals and diff);
  - the earlier, still unwired agent components;
  - small additions to `credential-vault.ts` (`saveSecret`/`loadSecret`) and
    `project-reader.ts` (`info`, `readHead`).
- `src/gwt/src/org/rstudio/studio/client/workbench/views/superrstudio/`:
  `ChatAiPane.java`, `ChatMarkdown.java`, `ChatEditReview.java`.
- Tests:
  - `tests/superrstudio/agent-*.test.cjs`;
  - `tests/superrstudio/desktop-chat*.cjs`;
  - `tests/superrstudio/fixtures/fake-gemini.cjs` and `make-chat-project.cjs`.

### Upstream files (listed with markers in `superrstudio/integration-points.json`)

- `src/node/desktop/src/main/gwt-callback.ts`: the `superr_chat_*` IPC
  handlers, which accept only the main window's main frame in experimental
  mode. The file also imports `createAliasedPath` from `../ui/utils`.
- `src/node/desktop/src/renderer/desktop-bridge.ts`: the `superrChat*`
  preload functions and one streaming listener.
- `RStudioGinjector.java`, `GlobalToolbar.java` and `PaneManager.java`: the
  toolbar button and the sidebar panel (the earlier visual commit).

### Repository tooling

- `.github/workflows/superr-checks.yml`: the agent tests listed in the
  `agent-components` job.
- `tools/superrstudio/test-gui-scatter.ps1`: the scenarios `chat`, `chat-ui`,
  `chat-project`, `chat-edit`, `chat-real`, `chat-real-project` and
  `chat-real-edit`. The `disabled` scenario also checks that Chat IA is absent
  and its IPC refused.

## Expected conflicts with `feature/auto-updater`

A read-only `git merge-tree --write-tree` against `origin/feature/auto-updater`
(`b405938d83`) reports content conflicts in exactly five files. In all five,
both branches add independent blocks at the same place. Keep both.

| File | Resolution |
| --- | --- |
| `gwt-callback.ts` | Keep both import groups and both handler blocks in the constructor. **Do not** register cleanup through `mainWindow.window.once('closed', …)` in the constructor. The upstream unit test `DesktopCallback` constructs `GwtCallback` with a stub that has no `window`, so it throws ("Cannot read properties of undefined (reading 'once')"). Chat IA uses `app.once('will-quit', …)` and reads `mainWindow.window` only when a call arrives. The updater block currently uses the failing pattern. |
| `desktop-bridge.ts` | Keep both groups of preload functions. |
| `integration-points.json` | Both add the keys `gwt-callback.ts` and `desktop-bridge.ts`. Merge each into one entry whose markers include both (`superr_chat_status` + `superr_check_for_updates`; `superrChatStatus` + `superrCheckForUpdates`). JSON cannot hold a key twice. Keep both sets of `superr_files`. |
| `superr-checks.yml` | Keep the `updater` job and the `agent-components` job with its test list; the merged path filters are the union. |
| `HANDOFF.md` | Keep both sections. |

After merging, run `python tools/superrstudio/check-integration.py`; it must
pass. Then run the checks below.

## Build

```powershell
tools\superrstudio\dev-build.ps1 -Component gwt -Force   # GWT draft; do not redirect stderr in PS 5.1
# Electron: copy changed src\node\desktop\src files to src\node\desktop-build-AMD64\src, then
Set-Location src\node\desktop-build-AMD64
$env:PATH = "D:\Git\rstudio-tools\dependencies\common\node\22.22.2;$env:PATH"
node node_modules\@electron-forge\cli\dist\electron-forge.js package
```

The package build (`tools\superrstudio\package-superr.ps1`) compiles GWT in
optimised mode and Electron through CMake, and needs nothing extra. Chat IA
adds no native module and no runtime dependency, and it uses Electron's
`safeStorage` and `net.fetch`. `src/node/desktop/CMakeLists.txt` globs
`src/*.ts` with `CONFIGURE_DEPENDS`, so the new TypeScript files are copied
and bundled. Only the TypeScript sources are bundled; the tests and fixtures
are not.

## Checks

| Check | Command | Uses Gemini quota |
| --- | --- | --- |
| 47 component tests | `node --test --require ts-node/register tests/superrstudio/agent-*.test.cjs` (environment as in `superr-checks.yml`) | no |
| Types | `tsc -p tests/superrstudio/agent-test-deps/tsconfig.json` and the desktop `tsc --noEmit` | no |
| Upstream desktop unit tests | `electron-mocha --config ./test/unit/mocharc.json` in `desktop-build-AMD64` | no |
| Desktop, simulated Gemini | `tools\superrstudio\test-gui-scatter.ps1 -Scenario chat,chat-ui,chat-project,chat-edit` | no |
| Regression | `-Scenario disabled,ggplot2,lfq,sheet,es,visual,theme` | no |
| Real, optional | `-Scenario chat-real` (1 request), `chat-real-project` and `chat-real-edit` (2 to 4 each) | yes, the owner's key in profile `gui-chat-real` |

Known failure unrelated to Chat IA: `Utils > findComponents returns session and
scripts paths`. It sets `RSTUDIO_CPP_BUILD_OUTPUT=/somewhere/interesting/`,
where no `rsession` exists. It fails the same way on `main` on this host. The
`deps` scenario needs an R whose own library has no ggplot2, which this host's
R no longer meets (see RELEASE-CHECKLIST.md).

## Release notes and documentation

- Merge [CHAT-IA-PREVIEW-NOTES.md](../release/CHAT-IA-PREVIEW-NOTES.md) into
  the next preview's `RELEASE-NOTES.md`, including the privacy and quota text.
- The Gemini API terms the owner should reconsider before wider distribution
  are in [chat-ia.md](chat-ia.md): age 18+, intended for developers, only paid
  services for EEA, Swiss or UK users.
