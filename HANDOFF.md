# SuperR handoff

Updated 2026-10-29 (fifth session: SuperR rename, Windows package, optional
packages, Beverton–Holt Z / yield per recruit), America/Montevideo, by Claude
Code (continuing Codex's work). The product is now **SuperR**; the
repository, directories and internal identifiers keep the `superrstudio`
names (owner decision, see docs/superrstudio/BRANDING.md).
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

## Fifth session: SuperR preview (2026-10-29)

Brief: "SUPERR — MASTER DEVELOPMENT AND FIRST PUBLIC PREVIEW RELEASE", plus
the owner's added requirement of on-demand R package installation.

| Item | State | Record |
| --- | --- | --- |
| Logo master and icon set (16–1024 px PNG, 10-size ICO, installer bitmaps, legibility sheet) | Done, reproducible: `tools/superrstudio/branding/make-branding.ps1` | docs/superrstudio/BRANDING.md |
| Central product identity `package/superr/product.json` (SuperR 0.1.0-preview.1) | Done; `tools/superrstudio/check-identity.ps1` checks the GWT, desktop and R copies | BRANDING.md |
| User-visible rename (window title, About dialog with notice and source link, menus, messages, generated comments) | Done; internal identifiers and file formats unchanged | BRANDING.md |
| Preliminary naming/trademark review | Done: **name not cleared** (no register search; repository name contains "rstudio") | docs/superrstudio/legal/superr-naming-review.md |
| Windows x64 installer `SuperR-0.1.0-preview.1-Windows-x64.exe` (CPack/NSIS, optimised, update check compiled out, unsigned) | Release candidate built from clean commit `541d0ad275`: 466.8 MB, SHA-256 `7695094cf7d5fade2e012525ea58bb13640c0180687e41be983fa86aea5c530e`, in `dist\superr\` (not in Git) | docs/superrstudio/packaging-windows.md |
| Side by side with RStudio (own folder/identity/ProgIDs, no default-program change, own settings in %APPDATA%/%LOCALAPPDATA%\SuperR) | Verified by `test-packaged.ps1` (no official RStudio installed here) | packaging-windows.md |
| Project compatibility (synthetic fixture, copy-and-compare script) | Fixture + `tools/superrstudio/test-project-copy.ps1` | docs/superrstudio/project-compatibility.md |
| Release automation | `.github/workflows/superr-release.yml` (manual, self-hosted runner, artifact; draft pre-release only after approval), `superr-checks.yml` (push checks) | docs/superrstudio/release/ |
| Beverton–Holt Z (mean length) and yield per recruit (TropFishR) | Done, verified against direct TropFishR and the published formulas | docs/superrstudio/features/lfq-tropfishr.md |
| On-demand installation of optional R packages (consent dialog, renv-aware) | Done | docs/superrstudio/features/optional-packages.md |
| Public pre-release | **Not published**: condition 1 (name clearance) not met | docs/superrstudio/release/RELEASE-CHECKLIST.md |

## Implemented and verified

1. **Visual scatter plot (first real feature, M3 slice)**, opt-in with
   `SUPER_RSTUDIO_EXPERIMENTAL=1`: Environment toolbar *Scatter* button, dialog
   to pick a data frame and two numeric columns, ggplot2 preview in the Plots
   pane of the active session, reproducible code exported to a new R script,
   appearance controls with undo/reset, colour-by-column, connected lines with
   explicit order and grouping, lm/LOESS fits with confidence bands and a
   fitted-model panel validated against reference R, and histogram/boxplot
   plot types plus bar (counts) and density, in the same non-modal editor
   window; tibbles and data.tables supported. 2026-10-28 (second session):
   **interactive preview with right-click editing** of points, lines, fits,
   bars/boxes/densities, titles, axes, legend, strips and panel (element map
   from gtable cells + `ggplot_build()` data; redo; legend position),
   **axes and facets** (log10, zoom vs filter limits, tick labels, gridlines,
   facet_wrap/grid; statistics on the transformed/filtered/per-panel data;
   spec schema 4) and **image export** (PNG/SVG/PDF via `ggsave()` with a
   reproducible script). Settings are in three accessible tabs. Third
   session: **date and date-time X axes** (`scale_x_date/datetime`, date
   breaks and labels, display time zone, ISO limits that zoom or filter,
   fits per day/second; spec schema 5) and a measured preview speed-up
   (paths counted by vertices: 100,000-row line previews 5.75 s -> 0.36 s).
   Details, design and evidence: [visual-scatter.md](docs/superrstudio/features/visual-scatter.md).
2. **Length-frequency analysis with TropFishR** (Milestone E first slice),
   opt-in, Environment toolbar *Length frequency*: data mapping and checks
   (rows removed per rule, per-date sample sizes, species), `lfqCreate` /
   `lfqRestructure` with TropFishR's plots, `ELEFAN_GA` (seeds) /
   `ELEFAN_SA` / `ELEFAN` in a separate Rscript process with progress and
   cancel, and a comparison of every run with its full configuration and
   code. Third session: **sampling period and quarterly samples**
   (`lfqModify`), recorded transformations, **what differs between
   configurations** (data, classes, restructuring, ranges, method, seeds,
   versions), **catch-curve mortality** (Pauly / cumulative, M from
   `M_empirical`, F, E, ogive, diagnostics) and **saved analyses** (versioned
   JSON file with data fingerprint and versions; restore, run again, rename,
   duplicate, delete, compare). Record: [lfq-tropfishr.md](docs/superrstudio/features/lfq-tropfishr.md).
   Messages: `tools/superrstudio/i18n/lfq_messages.py` generates English and
   Spanish together.
3. **Spanish for SuperRStudio windows** (third session): `ui_language` accepts
   `es` (General > Advanced, "SuperRStudio features only"); the windows select
   generated `*MessagesEs` classes at run time because a GWT `es` locale
   cannot compile without resources for 108 upstream interfaces. Upstream
   text stays English; numbers keep the decimal point; R code is never
   translated. Record: [spanish.md](docs/superrstudio/features/spanish.md).
4. **Design-system and branding foundation** (third session):
   `SuperRStudioTheme.java` (light/dark tokens, hint/status/busy/error
   styles, focus ring; contrast >= 4.5:1 checked in both themes) and
   `.rs.superrstudioBrand()` (one place for the product name in generated
   comments; file-format identifiers stay fixed).
5. **Dockable Visual workspace** (fourth session): a `Visual` workbench tab
   (suppressed unless the session reports `superrstudio_experimental`; new
   layouts keep it in the hidden tab set; saved layouts without it are
   migrated in `PaneConfig.validateAndAutoCorrect`) into which the one plot
   editor docks, keeping its state; float/dock buttons; zoom command.
   Record: [dockable-workspace.md](docs/superrstudio/features/dockable-workspace.md).
6. **One-click light/dark switch** (fourth session): sun/moon button in the
   global toolbar (experimental only) that sets the global `editor_theme`
   and applied theme like Appearance > Apply; remembers the last light and
   dark themes (per desktop profile). Record:
   [theme-toggle.md](docs/superrstudio/features/theme-toggle.md).
   **Resizable preview canvas** (fourth session): the preview is drawn at
   the canvas's physical size (spec schema 6); drag the corner, presets
   1:1/4:3/3:2/16:9, lock; export by exact dimensions or the preview's
   proportions. Record: visual-scatter.md, "Resizable preview canvas".
7. **Benchmarks** (third session): `tools/superrstudio/bench.ps1` (R level
   and desktop: baseline upstream build vs features off/on). Record:
   [benchmarks.md](docs/superrstudio/benchmarks.md).
   TropFishR 1.6.6 and its dependencies are installed only in the isolated
   test library (`.cache\superrstudio\r-library`).
8. **Development mode** (no installer): `tools/superrstudio/dev-build.ps1`,
   `dev-run.ps1`, `dev.ps1`, `dev-clean.ps1`, VS Code tasks via
   `install-vscode.ps1`. Usage: [BUILDING.md](BUILDING.md#superrstudio-development-mode-windows).
9. Windows baseline (Codex): full native/GWT/Electron build, R-session suites,
   live GUI smoke. [GUI record](docs/superrstudio/baseline/windows-gui-2026-10-28.md),
   [provisioning record](docs/superrstudio/baseline/windows-dependencies-2026-10-27.md).

## Exact commands to continue (PowerShell, from the checkout)

```powershell
tools\superrstudio\dev-build.ps1                 # incremental native + GWT
tools\superrstudio\dev-run.ps1 -Experimental     # launch with SuperRStudio features
$env:R_LIBS_USER="$PWD\.cache\superrstudio\r-library"; Rscript tests\superrstudio\visual-scatter.R
Rscript tests\superrstudio\lfq-tropfishr.R           # same R_LIBS_USER; TropFishR contract
tools\superrstudio\test-session.cmd experimental # upstream rsession suite
tools\superrstudio\test-gui-scatter.ps1          # live desktop acceptance (3 scenarios)
tools\superrstudio\test-gui-scatter.ps1 -Scenario lfq   # length-frequency window
tools\superrstudio\test-gui-scatter.ps1 -Scenario es    # Spanish windows
tools\superrstudio\test-gui-scatter.ps1 -Scenario visual  # Visual tab: old layout, restart, features off
tools\superrstudio\test-gui-scatter.ps1 -Scenario theme   # light/dark switch: toggle, remembered theme, restart, off
tools\superrstudio\bench.ps1 -Runs 3                    # benchmarks (R + desktop vs baseline)
python tools\superrstudio\i18n\lfq_messages.py         # regenerate LFQ + Spanish messages
```
`dev-run.ps1 -BuildDir <dir>` launches another native build (e.g. the
pristine baseline's) for comparisons.

Build tree: `build\superrstudio-windows` (Ninja, RelWithDebInfo, GWT_BUILD=OFF).
The Electron desktop build and runtime are reused from the baseline worktree /
`.cache\superrstudio\electron-runtime`. ggplot2 4.0.3, tibble 3.3.1 and data.table 1.18.6.1 are only in the isolated
library `.cache\superrstudio\r-library`; R 4.6.1 runtime, R 3.6.3 build input.

## Latest test results (2026-10-29 unless noted)

| Check | Result |
| --- | --- |
| `dev-build.ps1` native + GWT | PASS (no-op native ~2 s; GWT ~75 s, skipped when unchanged) |
| `visual-scatter.R`, R 4.6.1 + ggplot2 | PASS |
| `visual-scatter.R`, R 3.6.3 | PASS missing-package path; rendering SKIP |
| Upstream R-session suite on feature build, feature off and on | 654 passed / 655 (1 skipped), same as baseline (re-run 2026-10-28 after the LFQ module, feature on) |
| Live desktop scatter: ggplot2 (incl. appearance, undo, reset, colour mapping, lines, lm/loess fits, histogram, boxplot, right-click editing, axes/facets, export) / no-ggplot2 / disabled | PASS / PASS / PASS |
| Debug launch (DevTools 9222, Node inspector 9229), `-Wait` exit code | PASS |
| `lfq-tropfishr.R`, R 4.6.1 + TropFishR 1.6.6 / R 3.6.3 (2026-10-29, incl. preprocessing, comparison, saved analyses, catch curves) | PASS / PASS (missing-package path) |
| Live desktop length-frequency (`-Scenario lfq`, 2026-10-29, incl. seasonal GA, mortality, saved analyses) | PASS |
| Upstream R-session suite (feature on), after the LFQ completion and again after all third-session changes (incl. the ui_language header) | 654 passed / 655 (1 skipped), both times |
| `visual-scatter.R` incl. date/time axes and the SVG/PNG choice by vertices | PASS |
| Live desktop: ggplot2 (incl. sampling dates, dark theme, contrast) / no-ggplot2 / disabled / es / lfq | PASS / PASS / PASS / PASS / PASS (final builds of 2026-10-29) |
| Visual tab (`-Scenario visual`: migrate / restart / off) and regression ggplot2, no-ggplot2, disabled, es, lfq (fourth session) | PASS (all 8); upstream suite 654/655 |
| Theme switch (`-Scenario theme`: first / restart / off), canvas (in `ggplot2`), full GUI set no-ggplot2, disabled, es, lfq, visual (fourth session) | PASS |
| Benchmarks (`bench.ps1`, 3 runs + warm-up): ready baseline 3.32 s / off 3.34 s / on 3.41 s; console 29-30 ms; session 128 / 128 / 132 MB | recorded in docs/superrstudio/benchmarks.md |
| Fifth session: packaged release candidate (`test-packaged.ps1`: install, 4 launches nopkg/first/restart/off, uninstall, snapshots) | **66 checks, 0 failed** (Windows 11 x64; installed app starts in under 1 s after the first launch) |
| Fifth session: `deps.R`, `lfq-tropfishr.R` (incl. Beverton–Holt Z, yield per recruit), `visual-scatter.R` | PASS |
| Fifth session: live desktop ggplot2, no-ggplot2, disabled, lfq (incl. yield tab), es, visual ×3, theme ×3, deps | all PASS (ggplot2 once timed out after *Refresh data* and passed on rerun: intermittent) |
| Fifth session: upstream R-session suite, features on | 654 passed / 655 (1 skipped), unchanged |
| Fifth session: `check-identity.ps1`; desktop ESLint on the changed files | PASS (`tsc` could not run in place: the build copy has no node_modules after packaging) |

Known failures/limitations (unchanged from baseline unless noted):
`LoggingTest.CanJsonLogError` expects an English Windows message (host is
Spanish; not patched). npm audit findings remain open before distribution.
Spanish covers SuperRStudio windows only; R validation errors stay English. Dev launcher keeps
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
   density kinds. Done: *Load from script* restores a plot's specification
   from its generated code (foundation for structured editing).
   Done (second session): interactive right-click editing, axes/facets,
   image export, TropFishR length-frequency module (first slice).
   Done (third session): LFQ saved analyses, preprocessing options,
   comparison of configurations, seasonal GUI test, catch-curve mortality;
   Spanish windows; date/time axes; design-system/branding foundation;
   benchmark suite and the measured line-preview optimisation.
   Done (fourth session): dockable Visual tab with layout migration.
   Done (fourth session): light/dark switch; resizable preview canvas with
   export modes.
   Done: responsive docked layout (preview first in narrow panes); benchmarks
   of the new features (no start-up cost from features on vs off; canvas
   cost recorded in docs/superrstudio/benchmarks.md).
   Done: optimised-client benchmark (`dev-build.ps1 -Component gwt -Optimized`):
   start-up and Electron memory equal to the unmodified baseline.
   Done (fifth session): SuperR identity, installer, packaged tests, release
   workflows, Beverton-Holt Z / yield per recruit, optional packages on request.
   **Next exact tasks:** (1) owner: name clearance and repository-name decision
   (blocks the public pre-release, see docs/superrstudio/release/RELEASE-CHECKLIST.md);
   (2) register a self-hosted runner (labels self-hosted, Windows, X64,
   superr-build) and run superr-release.yml; (3) Windows 10 test machine;
   (4) dockable length-frequency window; (5) Thompson-Bell / VPA; domain review.
   Note: the working client may be the optimised build; the next normal
   `dev-build.ps1` recompiles the draft client (the draft stamp was removed).
   Then: remaining in-window preview overhead for 100,000-point scatter
   plots (2.4 s; R side 2.0 s is Cairo rasterisation of points), an
   optimised (non-draft) GWT build for memory comparisons with the
   baseline, Beverton-Holt Z / YPR for the LFQ module, domain review.
   Branding: the product is SuperR (fifth-session brief); public release
   only when the checklist's eight conditions hold ([BRANDING.md](docs/superrstudio/BRANDING.md)).
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
