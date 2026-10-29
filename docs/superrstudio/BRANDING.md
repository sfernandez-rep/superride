# Branding investigation (Milestone 6)

Status 2026-10-28: **investigated, not implemented.** Nothing in this fork
changes the product name, icons or About dialog yet. This is a technical
record, not legal advice.

Owner decision (2026-10-28): "SuperRStudio" remains the provisional
development identifier; the public/commercial name is decided before any
official binaries are distributed. Until then: keep branding changes modular
and reversible, preserve upstream copyright and licence notices, never imply
endorsement by Posit, publish no branded installers or releases, and add no
new public-facing uses of the RStudio trademark beyond the existing
provisional identifier. Preparing a branding system (one module per layer,
below) is allowed.

## Trademark and licence constraints

- **Trademark.** "RStudio" and the RStudio logos are trademarks of Posit
  Software, PBC. The AGPL-3.0 grants copyright permissions, not trademark
  rights (section 7(e) lets licensors decline trademark rights). A
  distributed derivative named **"SuperRStudio"** contains the mark and may
  suggest endorsement or cause confusion. Before any public release, obtain
  legal advice and/or Posit's permission, or choose a distinct name; never
  ship Posit/RStudio logos as the product's own. Factual attribution
  ("based on RStudio by Posit Software, PBC") remains appropriate.
- **Copyright and notices.** Keep `COPYING` (AGPL-3.0), `NOTICE` (third-party
  components) and upstream copyright headers. AGPL section 5(a) requires
  modified files to carry prominent notices of the modification and date:
  new files carry SPDX headers; a fork-level notice listing modified
  upstream files should accompany any release. Network use triggers the
  AGPL source-offer obligation (section 13) for server builds.
- **Separation from the official product.** A distributed build must not
  share RStudio's configuration/data directories, Windows app user-model ID,
  installer identity or update channel, or it would read and overwrite an
  installed RStudio's settings. The development launcher already isolates
  all of these through environment variables (BUILDING.md); a release needs
  them changed at the source.

## Where each brand surface lives (verified in this checkout)

| Surface | Location |
| --- | --- |
| Desktop window title (`<doc> - <edition>`) | `src/node/desktop/src/main/main-window.ts`, `gwt-callback.ts` (Electron main) |
| Edition name used by Electron | `src/node/desktop/src/main/activation-overlay.ts` (`editionName()`) |
| Edition name in the GWT client (document title, About) | `src/gwt/src/org/rstudio/studio/client/application/model/ProductEditionInfo.java` and its i18n constants |
| About dialog | `src/gwt/src/org/rstudio/studio/client/application/ui/AboutDialog.java` |
| Application metadata (`productName`, description) | `src/node/desktop/package.json`, Electron Forge config `forge.config.js` |
| File-type and app icons | `src/node/desktop/resources/icons`, `resources/freedesktop`, `package/win32` |
| Installer naming and identity | `package/win32/CMakeLists.txt`, `package/win32/cmake`, CPack settings |
| Config/data directory names | `src/cpp/core/system/Xdg.cpp` (session) and `src/node/desktop/src/core/xdg.ts` (Electron) |
| Theme colours / default appearance | `src/gwt/src/org/rstudio/core/client/theme/res/themeStyles.css`, editor themes under `src/cpp/session/resources/themes` |

## Recommended modular approach (once the name is decided)

1. One fork-owned branding module per layer instead of edits scattered in
   upstream files: a GIN-bound `ProductEditionInfo` subclass in GWT; a single
   branding constants file read by `activation-overlay.ts` in Electron;
   packaging variables in one CMake include.
2. Change identity (app ID, config/data directory names, installer GUID,
   update URL disabled) together with the name, and test side by side with
   an installed official RStudio.
3. Keep upstream credits in the About dialog and ship `COPYING`, `NOTICE` and
   a fork notice listing modified files.
4. Rebuild the Electron desktop in this checkout (the development launcher
   currently reuses the baseline's unmodified desktop build).

Until then, development builds are distinguished by their isolated profiles,
the `Plot editor` button (opt-in, `SUPER_RSTUDIO_EXPERIMENTAL=1`) and the
`SuperRStudio <kind> vN` header in generated code.

## Implemented so far (2026-10-29, foundation only)

- **R side.** `.rs.superrstudioBrand()` in `SessionSuperRStudio.R` is the one place for the product name. The generated comments and file notes of the SuperRStudio features use it: length-frequency preparation, run records, catch curves, and the saved-analyses note and messages.
- **Format identifiers are not branding.**
  - The `# SuperRStudio <kind> vN` headers and the `superrstudio-lfq-analyses` JSON format stay fixed under any future name, so that saved scripts and files keep loading.
  - The `srs-` CSS class prefix is also not part of the brand.
- **Client side.** The windows' look is defined once in `SuperRStudioTheme.java`, as design tokens and shared styles. A future visual identity can change those tokens without touching the dialogs.
- **Not touched.** No upstream logo, product name, installer, identity or About text has been changed, and no branded build is published.
