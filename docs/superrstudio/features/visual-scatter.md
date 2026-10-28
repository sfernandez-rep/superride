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

5. **Appearance** (added the same day, specification schema 2): plot title,
   X/Y axis titles, point colour (ggplot2 default or the colour-blind-safe
   Okabe-Ito palette), size, opacity and theme (grey, bw, minimal, classic,
   light). **Undo** steps back through appearance edits; **Reset appearance**
   restores ggplot2 defaults (and can itself be undone). Only non-default
   settings are emitted, so an unstyled plot still produces the minimal code.
6. **Colour by column**: map a numeric, character, factor or logical column
   to point colour, emitted as `colour = .data[["col"]]` inside `aes()` with a
   colour-blind-safe `scale_colour_viridis_d()` (categories) or
   `scale_colour_viridis_c()` (numbers). The fixed point colour is disabled
   while a column is mapped; R rejects requests combining both. Recorded as
   `colour_by` in the specification.

7. **Lines and fits** (specification schema 3). *Show*: points, connected
   lines, or lines and points. Connected lines always state their order:
   *in order of X* (`geom_line`, sorted within each group) or *in data-row
   order* (`geom_path`, only for rows that already form a sequence); the dialog
   explains the choice. Lines and fits can be grouped by a category (*Group
   lines/fits by*, `group = .data[["col"]]`). *Trend / fit*: none, linear
   regression (`geom_smooth(method = "lm", formula = y ~ x)`) or a LOESS
   smoother (`method = "loess"`, span 0.25-1), with optional confidence band
   and level (80-99 %). Line colour, width and type, and fit colour, are
   separate appearance settings.
8. **Fitted model panel.** For linear regression the dialog shows, per fitted
   group, n, the equation, R-squared, adjusted R-squared, the slope p-value and
   the residual standard error, all computed by `stats::lm()` on exactly the
   observations `geom_smooth()` uses, plus an explicit caveat that the fit is
   exploratory and its assumptions must be checked. Statistics are withheld
   (not invented) when a group has fewer than three observations or constant X.
   LOESS is reported as a descriptive smoother without an equation or R-squared.
   The exported script adds a `summary(stats::lm(...))` block that reproduces
   the model(s).

Generated code (the header records the versioned specification and versions):

```r
# SuperRStudio scatter v2
# Specification: {"schema_version":2,"kind":"scatter","dataset":"fish","x":"length cm","y":"mass_g","appearance":{"title":"Fish \"length\" vs mass","x_label":"Length (cm)","y_label":"","colour":"#0072B2","size":3,"alpha":0.6,"theme":"classic"}}
# R: 4.6.1; ggplot2: 4.0.3
ggplot2::ggplot(fish, ggplot2::aes(x = .data[["length cm"]], y = .data[["mass_g"]])) +
  ggplot2::geom_point(colour = "#0072B2", size = 3, alpha = 0.6) +
  ggplot2::labs(title = "Fish \"length\" vs mass", x = "Length (cm)") +
  ggplot2::theme_classic()
```

Appearance is sent as a JSON object (sixth RPC parameter), converted to an R
list in C++ and validated by `.rs.superrstudioScatterAppearance` (known keys,
types, text <= 200 characters, colour name or `#RRGGBB`, size 0.5-10, opacity
0.05-1, whitelisted themes). Layers are language objects; the displayed code
joins their deparsed forms, and the evaluated expression is the same
left-associated sum.

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
| R contract, R 4.6.1 + ggplot2 4.0.3 | `Rscript tests\superrstudio\visual-scatter.R` (isolated `R_LIBS_USER`) | PASS (line order/grouping; lm estimates vs `lm()` and closed-form least squares, R-squared vs `cor()^2`, p-value, confidence band vs `predict()`, per-group fits, LOESS vs `stats::loess()`, too-few withheld; plot equivalence, injection-shaped column names, stale/deleted data, revisions, limits, RPC wrapper) |
| R contract, R 3.6.3 (no ggplot2) | same with R 3.6.3 | PASS (missing-package path); rendering SKIP |
| Upstream R-session suite | `tools\superrstudio\test-session.cmd` (with and without `experimental`) | 654 passed of 655 (1 skipped), as baseline |
| Live desktop, ggplot2 | `tools\superrstudio\test-gui-scatter.ps1` | PASS: lines + points with explicit order hint, lm fit with 90 % band (dialog R-squared equals `summary(lm())`, band equals `predict(..., interval = "confidence")`), LOESS summary, discovery, no-numeric frame, numeric columns, Plots pane shows new plot, dataset unchanged, generated code reproduces plot data, appearance edits + undo + reset, styled code reproduces title/axis/colour/theme, colour-by-column (2 viridis colours), export identical, no client exceptions |
| Live desktop, no ggplot2 | same (`no-ggplot2`, empty library) | PASS: clean message in dialog, console unaffected, no device opened |
| Live desktop, disabled | same (`disabled`) | PASS: button hidden; ordinary IDE |

![Preview](visual-scatter-preview.png)
![Appearance](visual-scatter-appearance.png)
![Colour by column](visual-scatter-colour-by.png)
![Lines and linear fit](visual-scatter-lines-fit.png)
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
- The modal dialog must be closed to use the console and partly covers the
  Plots pane; a non-modal editor is planned for the ggplot2 editor milestone (M4).
- Text appearance fields commit on blur/Enter (GWT value-change semantics);
  undo history is per dialog and not persisted.
