# Visual scatter plot (M3 first slice) — acceptance record

Status: **implemented and verified in the live Windows 11 desktop**, 2026-10-28,
branch `feature/visual-scatter`. Opt-in: the session must be started with
`SUPER_RSTUDIO_EXPERIMENTAL=1` (`tools\superrstudio\dev-run.ps1 -Experimental`).

## What a user can do

1. Create or import a data frame in the R console.
2. Click **Scatter** in the Environment toolbar (next to *Import Dataset*).
3. Choose a data frame and two numeric columns; only plain data frames with
   unique, non-empty column names and ordinary integer/double columns are offered.
4. **Preview in Plots** renders `ggplot2` in the active session; the Plots pane
   is brought forward and ggplot2 warnings (for example removed NA rows) appear
   in the dialog. **Open R code** opens the same reproducible code in a new,
   unsaved R script. The dataset is never modified or copied into the
   user's environment.

Generated code (spec header records schema, dataset, columns and versions):

```r
# SuperRStudio scatter v1
# Specification: {"schema_version":1,"kind":"scatter","dataset":"fish","x":"length cm","y":"mass_g"}
# R: 4.6.1; ggplot2: 4.0.3
ggplot2::ggplot(fish, ggplot2::aes(x = .data[["length cm"]], y = .data[["mass_g"]])) + ggplot2::geom_point()
```

## Design

| Layer | File | Notes |
| --- | --- | --- |
| Session module | `src/cpp/session/modules/SessionSuperRStudio.{cpp,hpp,R}` | RPC `superrstudio_data` (`status`, `list`, `inspect`, `code`, `preview`, `release`); registered in `SessionMain.cpp`. Lists globals without forcing promises/active bindings. |
| R logic | `SessionSuperRStudio.R` | Code built as language objects (`substitute`/`deparse`), never by pasting user strings. A per-dialog revision plus serialized snapshot rejects data that changed after selection. Limits: 100,000 rows / 16 MiB. Validation failures are returned as data by `.rs.superrstudioDataRpc`, so they appear in the dialog and not in the console. |
| GWT | `workbench/views/superrstudio/*`, `EnvironmentPane.java` | `ScatterDialog` (ModalDialog; Close = Escape; ARIA status region), English messages plus `ScatterMessages_es.properties`. |

## Verification

| Check | Command | Result |
| --- | --- | --- |
| C++/GWT build | `tools\superrstudio\dev-build.ps1` | PASS |
| R contract, R 4.6.1 + ggplot2 4.0.3 | `Rscript tests\superrstudio\visual-scatter.R` (isolated `R_LIBS_USER`) | PASS (plot equivalence, injection-shaped column names, stale/deleted data, revisions, limits, RPC wrapper) |
| R contract, R 3.6.3 (no ggplot2) | same with R 3.6.3 | PASS (missing-package path); rendering SKIP |
| Upstream R-session suite | `tools\superrstudio\test-session.cmd` (with and without `experimental`) | 654 passed of 655 (1 skipped), as baseline |
| Live desktop, ggplot2 | `tools\superrstudio\test-gui-scatter.ps1` | PASS: discovery, no-numeric frame, numeric columns, Plots pane shows new plot, dataset unchanged, generated code reproduces plot data, export identical, no client exceptions |
| Live desktop, no ggplot2 | same (`no-ggplot2`, empty library) | PASS: clean message in dialog, console unaffected, no device opened |
| Live desktop, disabled | same (`disabled`) | PASS: button hidden; ordinary IDE |

![Preview](visual-scatter-preview.png)
![Export](visual-scatter-export.png)
![Missing ggplot2](visual-scatter-missing-ggplot2.png)

## Known limitations

- Spanish strings exist but are not compiled: the GWT module only builds
  `en,fr` (`RStudio.gwt.xml`). Adding `es` needs a locale permutation and the
  `ui_language` preference value; tracked for M7.
- Stale-data rejection is covered by the R contract test, not driven in the GUI
  (the modal dialog blocks console input).
- Only global-environment data frames; tibbles/data.tables (classed frames) are
  intentionally excluded in this slice.
- The modal dialog must be closed to use the console; a non-modal editor is
  planned for the ggplot2 editor milestone (M4).
