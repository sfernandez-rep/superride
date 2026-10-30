# Compatibility and regression plan

No full compatibility claim is made. Keeping upstream source unchanged does not
prove it works on this host. IDE compatibility is distinct from compatibility
among R versions, packages, native libraries and project lockfiles.

## Platform matrix

| Platform | Source configure/build | Desktop + R startup | Workflow regressions | Support claim |
| --- | --- | --- | --- | --- |
| Windows 11 x64 | Full native/GWT/Electron build PASS | Desktop version CLI PASS; embedded R-session tests PASS on 3.6.3/4.6.1; GUI not run | Native suites executed; one English-message assertion fails; GUI workflows not run | Primary target, partial validation |
| Windows 10 x64 | Not attempted | Not run | Not run | Experimental only |
| Ubuntu 24.04 x64 | Not attempted | Not run | Not run | Secondary target, unverified |
| WSL Ubuntu 24.04.3 | No build; shared Windows checkout integrity scan failed under different Git EOL settings | Not run | Not run | Does not certify native Linux |

Posit's [current user guide](https://docs.posit.co/ide/user/) lists Windows 11.
Windows 10 requires separate validation of the exact Electron/Chromium runtime,
native APIs, graphics stack and installer; never downgrade security components
to create an apparent compatibility result. No support conclusion follows from
an Electron version number alone.

## Acceptance matrix

GUI workflows below are **not run** against a live desktop window. Native/R-session
suite results are recorded in the [provisioning report](docs/superrstudio/baseline/windows-dependencies-2026-10-27.md).
Use an isolated test profile
and disposable projects, never real research data or the user's preferences.

| Area | Required observable result | Existing coverage / next test |
| --- | --- | --- |
| App / R startup | Window ready, selected R version visible, correct active R process | Existing Playwright harness, `panes/console/interpreter_version.test.ts` |
| Console / scripts / debugger | Evaluate `1+1`, source script, breakpoint and restart | `panes/console/`, `panes/debugger/`, editor suites |
| Projects | Open/save `.Rproj`, restore working directory and source tabs | `projects/create_projects.test.ts`, `close_project_after_open.test.ts`; add reopen assertions |
| Packages / CRAN | Load installed package; explicit install/remove in a disposable library | `panes/packages/packages_pane.test.ts`, `panes/console/package_installation.test.ts` |
| Bioconductor | Explicit repository selection, version compatibility and load | Add isolated integration test; no silent installation |
| renv | Open a lockfile project, restore only on explicit action, preserve library | Add lockfile/library before-after assertions |
| Import | CSV/TSV/Excel values, encodings, dates and missingness match reference | `panes/environment/import_dataset.test.ts`; extend format fixtures |
| Viewer | Correct sort/filter/page/refresh and object-deletion behavior | `panes/data-viewer/`, C++ `modules/data/DataViewerTests.cpp` |
| Transformations | Original preserved; derived result matches reference; stale edits rejected | Base-R fixture exists; future IDE transaction tests required |
| Graphics | Base and ggplot plots render, export dimensions/DPI correct | `panes/plots/plots_pane.test.ts`, `fixed_plot_size.test.ts`; add device/fidelity assertions |
| Plot specification | Validation, safe code generation, round trip and undo/redo | Not implemented; add with first plot operation |
| Reports | Render R Markdown/Quarto, error/warning output retained | `panes/editor/quarto*.test.ts`, layout render tests; extend R Markdown |
| Existing panes | Files, environment, history, help and terminal work | Existing pane suites |
| Git | Status/diff/commit and project worktree behavior | Existing VCS tests; use throwaway repositories |
| Preferences / themes / shortcuts | Existing values survive, keyboard focus and high-DPI layouts usable | Existing preference, layout and shortcut tests plus manual DPI checks |
| Scientific methods | Trusted numerical results, NA policy, assumptions, seeds and warnings | Initial standalone base-R reference only; per-method validation remains planned |
| Performance / cancellation | Responsive paged view; bounded memory; cancel leaves data consistent | Benchmark fixed 10k/100k/1M-row fixtures on recorded hardware before setting thresholds |

Paths in the coverage column are relative to `e2e/rstudio/tests/`, except the
C++ test. Inspect existing test preconditions before use. A test's existence is
not a passing result, and a zero-test or all-skipped run must not pass a gate.

## Checks introduced in this initialization

`tools/superrstudio/check-baseline.py` validates the local tag/commit, history,
license preservation and source paths. `--pristine` additionally rejects changes
to upstream application/build files. This is a source-integrity check, not an IDE test.

`tests/superrstudio/runtime-smoke.R` uses synthetic CSV/TSV data, including missing
values, non-syntactic column names and date/logical fields. It checks round-trip
values, a derived dataset, an analytically known linear regression and PDF export.
It uses only base/recommended R and temporary output. It exercises R itself;
it does **not** certify RStudio, ggplot2, Excel import or a scientific UI.

The GitHub foundation workflow runs those checks on `windows-2025` and
`ubuntu-24.04` with R 4.6.1. Windows Server CI does not replace Windows 11/10
desktop acceptance. Results must distinguish pass, fail, blocked and not run.

## Recording a baseline result

Store the revision, OS/build, R and package versions, compiler/SDK, test command,
exit status, report/log locations and known limitations in `docs/superrstudio/`.
Keep raw bulky logs, executables, caches and private datasets out of Git. Preserve
small relevant failure logs. Re-run affected suites after each substantive change;
run the matrix before a baseline upgrade or release. Never upgrade a project's
R environment, packages or renv lockfile as a side effect of a test.
