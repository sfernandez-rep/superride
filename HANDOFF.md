# SuperRStudio handoff

Updated 2026-10-28, America/Montevideo, by Claude Code (continuing Codex's work).
Continue this repository; do not restart initialization, recreate the GitHub
fork, clone RStudio again or reinstall verified dependencies. The original brief
is [PROJECT_BRIEF.md](docs/superrstudio/PROJECT_BRIEF.md); supplemental
instructions are in [CONTINUITY.md](docs/superrstudio/CONTINUITY.md).

## Objective and current checkpoint

Evolve RStudio Desktop into SuperRStudio, preserving the existing IDE and R
ecosystem while adding reproducible visual data/ggplot2/statistical workflows.
Windows 11 x64 comes first, Windows 10 remains experimental, Ubuntu 24.04 follows.

- Official fork: https://github.com/sfernandez-rep/superrstudio (already created).
- Active branch: `feature/visual-scatter` (not merged to `main`/`develop`).
  `git log -1 --oneline` is the authoritative HEAD. Milestone commits:
  `f2aabfc219` (Codex checkpoint), `5bc6a55ce2` (scatter feature verified),
  `9773e68319` (development workflow).
- Upstream tag `v2026.10.0+233`, commit `e961c6137d92315437caf5af53959f7110b517f9`.
- Main checkout `D:\Git\SuperRStudio`; pristine detached baseline worktree
  `D:\Git\SuperRStudio-baseline` (keep pristine); shared dependencies
  `D:\Git\rstudio-tools`.

## Implemented and verified

1. **Visual scatter plot (first real feature, M3 slice)**, opt-in with
   `SUPER_RSTUDIO_EXPERIMENTAL=1`: Environment toolbar *Scatter* button, dialog
   to pick a data frame and two numeric columns, ggplot2 preview in the Plots
   pane of the active session, reproducible code exported to a new R script,
   appearance controls with undo/reset, colour-by-column, connected lines with
   explicit order and grouping, lm/LOESS fits with confidence bands and a
   fitted-model panel validated against reference R, and histogram/boxplot
   plot types plus bar (counts) and density, in the same non-modal editor
   window (spec schema 3, `kind`); tibbles and data.tables supported.
   Details, design and evidence: [visual-scatter.md](docs/superrstudio/features/visual-scatter.md).
2. **Development mode** (no installer): `tools/superrstudio/dev-build.ps1`,
   `dev-run.ps1`, `dev.ps1`, `dev-clean.ps1`, VS Code tasks via
   `install-vscode.ps1`. Usage: [BUILDING.md](BUILDING.md#superrstudio-development-mode-windows).
3. Windows baseline (Codex): full native/GWT/Electron build, R-session suites,
   live GUI smoke. [GUI record](docs/superrstudio/baseline/windows-gui-2026-10-28.md),
   [provisioning record](docs/superrstudio/baseline/windows-dependencies-2026-10-27.md).

## Exact commands to continue (PowerShell, from the checkout)

```powershell
tools\superrstudio\dev-build.ps1                 # incremental native + GWT
tools\superrstudio\dev-run.ps1 -Experimental     # launch with SuperRStudio features
$env:R_LIBS_USER="$PWD\.cache\superrstudio\r-library"; Rscript tests\superrstudio\visual-scatter.R
tools\superrstudio\test-session.cmd experimental # upstream rsession suite
tools\superrstudio\test-gui-scatter.ps1          # live desktop acceptance (3 scenarios)
```

Build tree: `build\superrstudio-windows` (Ninja, RelWithDebInfo, GWT_BUILD=OFF).
The Electron desktop build and runtime are reused from the baseline worktree /
`.cache\superrstudio\electron-runtime`. ggplot2 4.0.3, tibble 3.3.1 and data.table 1.18.6.1 are only in the isolated
library `.cache\superrstudio\r-library`; R 4.6.1 runtime, R 3.6.3 build input.

## Latest test results (2026-10-28)

| Check | Result |
| --- | --- |
| `dev-build.ps1` native + GWT | PASS (no-op native ~2 s; GWT ~75 s, skipped when unchanged) |
| `visual-scatter.R`, R 4.6.1 + ggplot2 | PASS |
| `visual-scatter.R`, R 3.6.3 | PASS missing-package path; rendering SKIP |
| Upstream R-session suite on feature build, feature off and on | 654 passed / 655 (1 skipped), same as baseline |
| Live desktop scatter: ggplot2 (incl. appearance, undo, reset, colour mapping, lines, lm/loess fits, histogram, boxplot) / no-ggplot2 / disabled | PASS / PASS / PASS |
| Debug launch (DevTools 9222, Node inspector 9229), `-Wait` exit code | PASS |

Known failures/limitations (unchanged from baseline unless noted):
`LoggingTest.CanJsonLogError` expects an English Windows message (host is
Spanish; not patched). npm audit findings remain open before distribution.
Spanish UI strings are not compiled (GWT builds only `en,fr`). Dev launcher keeps
a non-interactive caller's pipe open unless run in the background or with `-Wait`.

## Next actionable tasks

1. Done: scatter appearance controls (title, axis titles, Okabe-Ito colour,
   size, opacity, theme, undo/reset; spec schema 2) — desktop-verified.
2. Done: colour-by-column (viridis discrete/continuous scale), desktop-verified.
3. Done: lines, ordering, grouping, lm/LOESS fits and model statistics.
   Done: histogram and boxplot kinds (statistics equal ggplot2's).
4. Done: non-modal, draggable editor window (Plots pane and console usable
   while it is open; stale data detected). Done: tibble/data.table
   support with copy-free staleness checks (Milestone 4). Done: bar (counts) and
   density kinds. **Next:** a property-editor foundation for contextual
   editing on the structured specification, saving/loading specifications,
   and development branding (Milestone 6).
5. M4 groundwork: saving/loading specifications and contextual editing on a
   structured specification (not on the raster image).
6. Before release: dependency audit, localized logging test, `es` locale build.

## Continuing in Codex or Claude Code

Read this file, AGENTS.md, CLAUDE.md and ROADMAP.md; inspect `git status`,
`git log -1` and existing worktrees. Do not repeat completed dependency/build
work. Upstream edit hooks in `.claude/hooks/` need Git Bash; on this host it is
Scoop's (`CLAUDE_CODE_GIT_BASH_PATH` set in user settings) — do not bypass them.
Keep small coherent commits, push verified progress, and update this handoff at
each milestone. There is no automatic transfer between agents; this file is the
handoff. Graphify: `tools/superrstudio/graphify-local.ps1`, see
`docs/superrstudio/graphify.md` (local only; verify hits against source). Do not
install Ponytail.
