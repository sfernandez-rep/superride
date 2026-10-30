# SuperR 0.1.0-preview.1 release checklist

A public GitHub pre-release is allowed only when **all eight** conditions
below hold. Otherwise the installer stays a workflow artifact or a local
build, and the reason is recorded here.

Status at the last update: **not published.**

- **Condition 1 is not met:** the name is not cleared.
- Condition 3 is met for the release candidate built from `541d0ad275`
  (66 checks, 0 failed).

| # | Condition | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Trademark and naming review clear | **Not met** | [Preliminary review](../legal/superr-naming-review.md). No conflict was found by web search, but there has been no register search (USPTO/EUIPO/WIPO, classes 9 and 42). The repository was renamed to `superride` on 2026-10-29. Owner action required: register search or legal advice |
| 2 | Licence and source obligations | Met for the package contents | The package contains `COPYING` (AGPL-3.0) and `NOTICE` (third-party), and the About dialog has the licence, the trademark notice and the source link. The release assets add `SOURCE.txt` (commit, source archive) and `MODIFIED-FILES.txt` (AGPL §5(a): files changed against upstream `e961c6137d`) |
| 3 | Installer and packaged tests pass | Met (2026-10-29) | `tools/superrstudio/test-packaged.ps1` on `SuperR-0.1.0-preview.1-Windows-x64.exe` built from `541d0ad275` (SHA-256 `7695094cf7d5…a5c530e`): 66 checks, 0 failed, Windows 11 x64 |
| 4 | Side-by-side behaviour verified | Partly | Own folder, shortcut, uninstall entry, `SuperR.*` ProgIDs, no default-program change, RStudio settings folders untouched, uninstall leaves RStudio keys alone. **No official RStudio is installed on the test machine**, so running both at the same time is unverified |
| 5 | No private data or secrets | Met (scan below) | Staged package scanned: no user-profile paths and no credentials. Token-like strings are detection regexes inside the Copilot language server. Build paths under `D:\Git\SuperRStudio` remain in native binaries' debug directories, as in any MSVC build |
| 6 | Windows claims match evidence | Met | Windows 11 x64 only. Windows 10 is stated as untested |
| 7 | Clearly experimental | Met | Version `0.1.0-preview.1`, About dialog "Preview" and pre-release ribbon, release notes "experimental preview" |
| 8 | Provenance documented | Met | `*.provenance.json` (commit, versions, toolchain, unsigned), `.sha256`, `SOURCE.txt`; the CI workflow builds from a commit |

## Test record

Last run: 2026-10-29, Windows 11 Pro for Workstations x64, R 4.6.1 (registered),
66 checks, 0 failed. Evidence (screenshots of the SuperR window only, results.json,
before/after snapshots) stays in `.cache/superrstudio/packaged-tests/` and is not
committed. The 20
scenarios of the brief map to these checks:

| # | Scenario | Check |
| --- | --- | --- |
| 1 | Fresh install | silent per-user install exits 0, own folder; first start with an empty user library (`nopkg` phase) |
| 2 | Start Menu | `SuperR.lnk` → `SuperR.exe` |
| 3 | Taskbar icon | executable icon equals `superr-32.png` (mean channel difference < 8); window capture |
| 4 | Theme | `first`: one-click switch to dark; `restart`: remembered |
| 5 | R discovery | R version printed in every phase (registered R found without settings) |
| 6 | Scripts | `R/analysis.R` with relative paths runs and writes its outputs |
| 7 | Packages | ggplot2 used from the session library; optional-package dialog on first start |
| 8 | RStudio project | `.Rproj` opened, working directory at the project |
| 9 | ggplot2 | analysis PNG, plot editor code evaluates to a ggplot |
| 10 | Visual editing | plot editor docked in the Visual tab with lm fit |
| 11 | Dock / undock | float and dock again with state kept |
| 12 | Exports | PNG export from the editor into the project |
| 13 | Restored dimensions | Visual tab layout restored after restart. Window size restore is not measured |
| 14 | Spanish | `ui_language` "es" at restart: SuperR windows in Spanish |
| 15 | TropFishR | length-frequency window opens (TropFishR from the test library) |
| 16 | Restart layout | Visual tab restored |
| 17 | Features off | `SUPER_RSTUDIO_EXPERIMENTAL=0`: no Visual tab, switch or editor buttons |
| 18 | Coexistence with RStudio | settings folders and RStudio ProgIDs unchanged; a simultaneous RStudio was not run (none installed) |
| 19 | Clean uninstall | folder, shortcut, uninstall entry, App Paths and ProgIDs removed; user settings and projects kept |
| 20 | Original files unchanged | fixture hashes and R libraries identical before and after |

## Signing

The installer is unsigned (no code-signing certificate). See
[packaging-windows.md](../packaging-windows.md#signing).

## To publish (owner)

1. Resolve condition 1: record the register search or legal advice (the
   repository is already renamed to `superride`).
2. Run *SuperR Windows preview build* (`superr-release.yml`) on the
   self-hosted runner with `create_draft_prerelease`. Approve the
   `superr-release` environment.
3. Check the draft: assets, SHA-256, notes. Then publish it as a
   **pre-release**.
