# SuperR branding

Status 2026-10-29: **implemented for the Windows x64 package.** The product
is **SuperR** (owner decision in the 2026-10-29 brief, replacing the
provisional development name "SuperRStudio"). This is a technical record, not
legal advice. Naming and trademark review:
[legal/superr-naming-review.md](legal/superr-naming-review.md) (preliminary;
the name is **not cleared** for a public release yet).

## Rules kept

- **Notices and credit.** Upstream copyright, the AGPL-3.0 (`COPYING`), the
  third-party notices (`NOTICE`) and the About dialog's RStudio trademark and
  licence text are kept. The About dialog, the installer's version
  information, the release notes and the documentation state: "SuperR is an
  independent fork of RStudio. It is not developed, endorsed or supported by
  Posit Software, PBC. RStudio is a trademark of Posit Software, PBC."
- **No Posit marks as SuperR's own.** The product name, executable,
  installer and application icon carry no RStudio name or logo. Factual
  references ("based on RStudio 2026.10.0") remain.
- **Compatibility over renaming.** User-visible names change; internal
  identifiers do not:
  - namespaces, the `.rs.*` R API, RPC and preference names;
  - the RStudio version reported to R packages;
  - saved-file formats (`# SuperRStudio <kind> v6` plot specifications,
    `superrstudio-lfq-analyses`);
  - the `SUPER_RSTUDIO_EXPERIMENTAL` switch.
- **The repository and local directory keep their names** (`superrstudio`)
  until the owner decides otherwise.

## Logo and generated assets

| Item | Location |
| --- | --- |
| Master (approved, unmodified; arrived as `logo-master.png.png`, renamed only, SHA-256 `8414FD72…34B3A6`) | `assets/branding/source/logo-master.png` (1376 × 1143 RGBA) |
| Generator (PowerShell + System.Drawing, no extra software) | `tools/superrstudio/branding/make-branding.ps1` |
| Icons 16, 20, 24, 32, 40, 48, 64, 96, 128, 256, 512, 1024 px | `assets/branding/generated/png/` |
| Windows icon (10 sizes; 32-bit DIB up to 128 px, PNG at 256 px) | `assets/branding/generated/superr.ico` |
| Installer header (150 × 57) and welcome/finish (164 × 314) bitmaps | `assets/branding/generated/installer-*.bmp` |
| Legibility sheet (light, dark, checkerboard; small sizes magnified) | `assets/branding/generated/contact-sheet.png` |
| Source hash, cleanup counts, output hashes | `assets/branding/generated/manifest.txt` |
| About-dialog logo (copy of the 96 px icon) | `src/gwt/.../views/superrstudio/superr-logo-96.png` |

**Cleanup.** Analysis of the master found:

- the body is drawn at alpha 253 instead of 255;
- 16,352 near-invisible haze pixels (alpha 1–15) are spread over the whole
  canvas;
- the edges are clean (312 dark semi-transparent pixels).

The generator works on an in-memory copy:

1. It removes the haze (alpha < 16 → 0) and makes the body opaque
   (alpha 248–254 → 255). It keeps the edge antialiasing.
2. It crops to the content (899 px) and centres it on a square, so
   proportions are unchanged.
3. It downsizes with premultiplied alpha (no dark halo), halving
   progressively and then using one bicubic step.

Small sizes use a 3 % margin and larger ones 6 %. The R stays recognisable
at 16 px on light and dark backgrounds (`contact-sheet.png`).

**Not produced:**
- a splash screen. The Electron desktop shows none beyond its loading page;
  upstream's `splash.html` is unbranded text;
- macOS `.icns` and Linux icons, because only Windows is packaged.

The file-type icons (`.R`, `.Rproj`, …) stay upstream's generic R document
icons.

## Where each surface lives

| Surface | Implementation |
| --- | --- |
| Product identity (single source) | `package/superr/product.json`; consistency check `tools/superrstudio/check-identity.ps1` |
| Window title, dialogs (Electron) | `activation-overlay.ts` `editionName()` → `superr-identity.ts` |
| Document title, About title (GWT) | `rStudioEditionName=SuperR{0}` in `StudioClientApplicationConstants_*.properties` |
| About dialog | `AboutDialogContents.*`: SuperR logo, SuperR version, "Based on RStudio <version>", independence notice and source link |
| Executable name, version resource, icon | `forge.config.js` (Windows), `install-fuses.mjs`, `src/node/desktop/CMakeLists.txt` |
| Installer, registry, shortcuts | `package/CMakeLists.txt`, `package/win32/superr-registry.cmake`, `NSIS.template.in` |
| User settings folders | `superr-identity.ts` (`RSTUDIO_CONFIG_HOME` / `RSTUDIO_DATA_HOME` defaults in the packaged app) |
| Generated code comments and messages | `.rs.superrstudioBrand()` (`SessionSuperRStudio.R`) |
| Menu labels of the SuperR features | `Commands.cmd.xml` (`Show Visual (SuperR)`), plot editor and preferences texts |
| Look of the SuperR windows | design tokens in `SuperRStudioTheme.java` |

Packaging and side-by-side design: [packaging-windows.md](packaging-windows.md).

## Known remaining "RStudio" texts

Upstream menus, dialogs and help still name RStudio in many places, for
example:

- *RStudio Docs*;
- messages that refer to "RStudio";
- the Help pane;
- the server edition label.

They describe upstream functionality and documentation. Rewriting hundreds
of upstream strings would make every upstream merge conflict, so they are
listed as a known limitation rather than changed.
