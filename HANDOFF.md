# SuperRStudio handoff

Updated 2026-10-28, America/Montevideo. Continue this repository; do not restart
initialization, recreate the GitHub fork, clone RStudio again or reinstall
verified dependencies. The original brief is [PROJECT_BRIEF.md](docs/superrstudio/PROJECT_BRIEF.md).
The latest supplemental instructions are [CONTINUITY.md](docs/superrstudio/CONTINUITY.md).

## Objective and current checkpoint

Evolve RStudio Desktop into SuperRStudio, preserving the existing IDE and R
ecosystem while adding reproducible visual data/ggplot2/statistical workflows.
Windows 11 x64 comes first, Windows 10 remains experimental, Ubuntu 24.04 follows.
No visual SuperRStudio feature has been implemented yet; no mockup counts as one.

- Official fork: https://github.com/sfernandez-rep/superrstudio (already created).
- Active branch at this checkpoint: `feature/windows-build-environment`.
- Prior implementation checkpoint: `abb1a48023` (continuity instructions).
  This handoff is committed after that checkpoint; `git log -1 --oneline` is the
  authoritative current HEAD, avoiding a self-referential commit hash in this file.
- Upstream tag: `v2026.10.0+233`, RStudio Desktop 2026.10.0, Blue Mistflower.
- Exact upstream: `e961c6137d92315437caf5af53959f7110b517f9`.
- Main fork checkout: `D:\Git\SuperRStudio`.
- Existing pristine detached baseline worktree: `D:\Git\SuperRStudio-baseline`.
- Shared downloaded/build dependencies: `D:\Git\rstudio-tools`.
- `main` and `develop` currently contain the earlier foundation; environment work
  is pushed on the feature branch. Do not overwrite or force-push other branches.

## Architecture and installed tools

Reuse C++/R session modules in `src/cpp`, Java/GWT workbench in `src/gwt`, and
TypeScript/Electron in `src/node/desktop`. Transport is existing JSON-RPC/events
and resource handlers. See [ARCHITECTURE.md](ARCHITECTURE.md). Viewer caches are
not write authority; visual operations must use the active R session and emit R.

Verified: VS Build Tools 2026 18.7.3 (build 18.7.11925.98), MSVC 145/compiler
19.51.36248, Windows SDK 10.0.26100.0, portable CMake 4.3.4/Ninja 1.13.1, Temurin
17.0.20.1+1, Ant 1.10.18, Python 3.13.15, Strawberry Perl 5.42.3, NSIS 3.12, jq
1.8.2, Node 22.22.2 (build)/24.21.0 (bundled), R 3.6.3 (build)/4.6.1 (runtime),
Quarto 1.10.18, Boost 1.91.0, SOCI 4.0.3, OpenSSL 3.1.4 and libclang 13.0.1.
Exact locations/evidence: [provisioning record](docs/superrstudio/baseline/windows-dependencies-2026-10-27.md).

## Build and validation already executed

From Command Prompt in the fork, configure this shell only:

```bat
call tools\superrstudio\enter-windows.cmd
cd /d D:\Git\SuperRStudio-baseline
cmake --build build\baseline-windows --parallel 4
```

The existing full build completed with **exit 0**, including GWT, native backend,
native Node add-ons, Electron packaging and fuses. Do not rebuild unless a change
requires it. The helper selects UTF-8 console code page 65001; code page 850
caused garbled localized MSVC include prefixes and zero Ninja header dependencies.
This was fixed and verified (350 headers for a representative C++ object).
CMake 3.31 is insufficient for MSVC 145; the tested portable pin is 4.3.4.

Existing build root: `D:\Git\SuperRStudio-baseline\build\baseline-windows`.
Existing desktop output:
`D:\Git\SuperRStudio-baseline\src\node\desktop-build-amd64\out\RStudio-win32-x64\rstudio.exe`.
Backend: `build\baseline-windows\src\cpp\session\rsession.exe` and
`rsession-utf8.exe`. Dev configuration: `build\baseline-windows\src\cpp\conf\rdesktop-dev.conf`.
Upstream CMake reconfiguration recreates `src/node/desktop-build-amd64`; avoid
unnecessary reconfiguration that would discard its installed npm dependencies.

| Executed check | Result |
| --- | --- |
| Full Windows native/GWT/Electron build | PASS, exit 0; source worktree remains pristine |
| Desktop `--version-json` | PASS; RStudio 2026.10.0-baseline+233, Electron 43.7.7, Chrome 150.0.7871.250 |
| `rsession.exe --version` | PASS |
| Core native suite | 658 pass, 1 fail, 5 skip |
| Shared-core suite | 17 pass |
| R-session suite, R 3.6.3 | 652 pass, 3 skip, exit 0 |
| UTF-8 R-session suite, R 4.6.1 | 654 pass, 1 skip, exit 0 |
| Standalone R fixture, both R versions | PASS: import/NA/types/transform/lm/PDF |
| Source provenance and license check | PASS |
| Live desktop GUI / console / project workflows | PASS: R 4.6.1, import, lm, plot, CSV/PDF, editor save, project open; no client exceptions |

The one core failure is `LoggingTest.CanJsonLogError`, `LoggingTests.cpp:773`:
the test expects an English Windows system message; this host returns the
correct Spanish translation. Do not change OS language or claim this test passed.
The baseline test has not been patched. npm audit reports 33 dependency entries
including dev dependencies; production-only has `source-map-js` (high) and
`fast-uri` (moderate). No forced updates were applied. Review before distribution.
No installer, GUI compatibility certification or scientific UI exists yet.

## Current work and exact next action

1. Implement the next real feature on `feature/visual-scatter`: an opt-in C++/R
   session module and GWT dataset/column dialog, same-session ggplot2 preview and
   generated R code. Read-only data initially; validate stale objects and cancel.
2. Reuse existing build/dependencies; build changed source in the main checkout,
   keeping the detached baseline source pristine. Install ggplot2 only in the
   isolated test library if required; do not alter a research project's renv.
3. Keep the documented dependency audit open before distribution. The single
   logging-test failure is an OS-language expectation, not a demonstrated runtime
   failure; fix its test portably in a separate change when appropriate.

Graphify Labs `graphifyy==0.9.97` is installed in a project-local venv. See
`docs/superrstudio/graphify.md` and `tools/superrstudio/graphify-local.ps1`.
Full local `src` graph: 87,531 nodes / 241,592 edges, 4,586 code files scanned.
No cloud/model/MCP/global skill was enabled. Parsing is incomplete (especially
R helpers); graph hits must be checked against source. Do not install Ponytail.
GUI smoke scripts: `tools/superrstudio/launch-desktop-smoke.cjs` and
`tests/superrstudio/desktop-smoke.cjs`. See the GUI acceptance record for commands.
Runtime logs, installer records and audit JSON are in `.cache/superrstudio/`;
small committed evidence is in `docs/superrstudio/baseline/`.

## Continuing in Codex or Claude Code

Read this file, AGENTS, CLAUDE and ROADMAP; inspect `git status`, `git log -1` and
the existing worktrees. Do not repeat completed dependency/build work. Keep small
coherent commits and push verified progress to the existing fork. Update this
handoff at each meaningful milestone and before ending. Quota remaining is not
exposed here; do not claim an exact balance. Preserve recoverable progress early.

Suggested continuation prompt: "Read HANDOFF.md and the supplemental continuity
instructions. Continue the exact next unfinished action, verify it, commit it,
update the handoff, and advance to the next roadmap milestone when feasible."
There is no verified automatic transfer between Codex and Claude Code; this is
a file-based handoff. Do not launch another agent through unverified commands.
