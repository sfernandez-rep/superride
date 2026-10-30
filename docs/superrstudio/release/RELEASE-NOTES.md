# SuperR 0.1.0-preview.1 (experimental preview, Windows x64)

**Experimental software. Not for production analyses.** SuperR is an
independent fork of RStudio Desktop that adds visual tools for scientific
work (biology, ecology, marine science, fisheries). It is not developed,
endorsed or supported by Posit Software, PBC. RStudio is a trademark of
Posit Software, PBC.

## What is in this preview

- **Visual plot editor:** scatter, lines, histogram, boxplot, bar and density
  plots; lm and LOESS fits; facets and axes. It writes clean ggplot2 code and
  exports the plot. You can use it docked in the *Visual* tab or as a
  floating window.
- **Length-frequency window (TropFishR):**
  - preprocessing, ELEFAN growth, catch-curve mortality, Beverton–Holt Z
    from mean length and yield per recruit, computed by TropFishR's own
    functions;
  - comparison of configurations, saved analyses and reproducible code.
- **One-click light/dark theme switch and Spanish:**
  - the theme switch is in the global toolbar;
  - Spanish is available for the SuperR windows.
- **Optional R packages on request:** ggplot2 and TropFishR are offered for
  installation when a window needs them, never installed without consent.
- **Everything else is RStudio 2026.10.0** (build 233) as released upstream.

## Install

1. Download `SuperR-0.1.0-preview.1-Windows-x64.exe` and its `.sha256` file.
2. Optional: verify the download in PowerShell with
   `(Get-FileHash .\SuperR-0.1.0-preview.1-Windows-x64.exe).Hash` and compare
   it with the `.sha256` file.
3. Run the installer. It installs either for the current user only (no
   administrator rights) or, with administrator rights, for all users.

The installer is **not digitally signed**, so Windows SmartScreen shows
"Windows protected your PC". Check the SHA-256 first. Then choose *More info →
Run anyway* only if you trust this download. Never disable Defender or
SmartScreen.

**R:** SuperR needs R installed separately (from CRAN). It uses the same R
and the same package libraries as RStudio. The plot editor needs ggplot2 and
the length-frequency window needs TropFishR. SuperR does not need them at
start-up: when you open one of these windows without its package, SuperR
shows what it would install (package, dependencies, source, library) and
installs only if you choose *Install*. Under renv, packages go into the
project library and `renv.lock` is left unchanged. SuperR never updates
packages by itself.

## Next to RStudio

SuperR installs into its own folder and keeps its own settings
(`%APPDATA%\SuperR`, `%LOCALAPPDATA%\SuperR`). It does not change RStudio,
its settings, or the default program of `.R`, `.Rproj`, `.Rmd` or `.qmd`
files. SuperR only appears under *Open with*. Projects are not converted: the
same `.Rproj` folder opens in both.

Test an existing project on a copy first. `tools\superrstudio\test-project-copy.ps1`
in the source makes the copy, opens it in SuperR, and reports which files the
session changed. Running scripts can create or overwrite their outputs.

## Uninstall

Use *Settings → Apps → SuperR → Uninstall*. This removes the program, the
shortcut and SuperR's registry entries. It keeps your projects, data, R
libraries and SuperR's settings folders. Delete those folders by hand if you
no longer need them.

## Tested

Results for this build are in `docs/superrstudio/release/RELEASE-CHECKLIST.md`
at the release commit.

| Item | Status |
| --- | --- |
| Windows | Windows 11 x64 tested. Windows 10 not tested |
| R | R 4.6.1 tested (plus R 3.6.3 for the missing-package paths) |

## Known limitations

- The SuperR features are an experimental preview, and their scientific
  results need review by domain experts. TropFishR computes the estimates;
  SuperR does not alter them.
- Many upstream menus and messages still say "RStudio". These refer to
  RStudio functionality and documentation.
- Spanish covers the SuperR windows only. The rest of the IDE stays in
  English.
- The installer is unsigned. There are no automatic updates: check the
  repository for new versions.
- Windows 10, Windows on ARM, macOS and Linux packages are not available or
  not verified.

## Source and licence

SuperR is licensed under the GNU Affero General Public License v3 (`COPYING`),
like RStudio. Third-party notices are in `NOTICE` and in the application's
*Help → About → Open Source Components*. The corresponding source for this
build is the commit named in `SOURCE.txt` and in the provenance file.
