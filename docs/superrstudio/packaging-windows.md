# SuperR Windows x64 packaging

How the SuperR installer is built and why it can be installed beside RStudio.
Status and test evidence: [release checklist](release/RELEASE-CHECKLIST.md).

## Build

```powershell
tools\superrstudio\package-superr.ps1            # configure once, build, installer
tools\superrstudio\package-superr.ps1 -Quick     # build only, no installer
tools\superrstudio\test-packaged.ps1             # install, test, uninstall
```

`package-superr.ps1` follows upstream's `package\win32\make-package.bat`, with
the pinned toolchain from `enter-windows.cmd`:

| Step | What happens |
| --- | --- |
| Configure | `build\superr-package`: Ninja, `RelWithDebInfo` (optimised `/O2`, as upstream release builds), `RSTUDIO_PACKAGE_BUILD=1`, `GWT_BUILD=1` with the `RStudioDesktop` module compiled by `gwtc` (optimised), `RSTUDIO_DISABLE_CHECK_FOR_UPDATES=1` |
| Version | The session reports `2026.10.0-preview+233`: the upstream release it is based on, so R packages that check the RStudio version (rstudioapi) behave as with that release. SuperR's own version (`0.1.0-preview.1`) is shown in the About dialog, the installer and Apps & features |
| Build | Session, panmirror, GWT client, Electron desktop as `SuperR.exe` (Electron Forge with `forge.config.js`), Electron fuses |
| Icons | ResourceHacker adds the file-type icon groups 2 to 15 to `SuperR.exe`, as `make-package.bat` does |
| Installer | CPack/NSIS (staging under `C:\rsbuild`, upstream's short path); output moved to `dist\superr\` with `.sha256` and `.provenance.json` (commit, versions, toolchain, unsigned) |

`dist\` and `build\` are ignored by Git; installers are never committed.

## Identity

`package/superr/product.json` is the single source of the product identity.

**Read directly** by:
- `package/superr/superr-product.cmake`, which `package/CMakeLists.txt` and `src/node/desktop/CMakeLists.txt` include;
- `package/win32/superr-registry.cmake`;
- `src/node/desktop/forge.config.js`;
- `src/node/desktop/scripts/install-fuses.mjs`.

**Copies** that cannot read it, each checked by `tools/superrstudio/check-identity.ps1`:
- `SuperRProduct.java` (GWT);
- `superr-identity.ts` (desktop);
- `rStudioEditionName` in the client constants;
- `.rs.superrstudioBrand()` (R).

| Surface | SuperR value |
| --- | --- |
| Application, window title, About dialog | SuperR |
| Executable | `SuperR.exe` (product name, company, description in its version resource; SuperR icon) |
| Installer | `SuperR-0.1.0-preview.1-Windows-x64.exe` (the brief's short name `SuperR-Preview-Windows-x64.exe` is kept for an unversioned alias only) |
| Install folder | `%LOCALAPPDATA%\Programs\SuperR` (per user) or `%ProgramFiles%\SuperR` (all users) |
| Start Menu | `SuperR.lnk` |
| Apps & features | `SuperR 0.1.0-preview.1`, publisher "SuperR contributors" |
| Registry | `Software\SuperR contributors\SuperR`, uninstall key `SuperR`, `App Paths\SuperR.exe`, ProgIDs `SuperR.*` |
| User settings | `%APPDATA%\SuperR` (preferences, desktop state) and `%LOCALAPPDATA%\SuperR` (sessions, logs) |

**Not renamed, on purpose.** These keep their RStudio names:
- internal identifiers: C++ and Java namespaces, the `.rs.*` R API, RPC names, preference keys;
- the `rstudioapi` contract;
- saved-file formats (`# SuperRStudio <kind> v6` plot specifications, `superrstudio-lfq-analyses`);
- the `SUPER_RSTUDIO_EXPERIMENTAL` switch.

Renaming them would break saved work, R packages and upstream merges.

## Side by side with RStudio

| Concern | How SuperR avoids it |
| --- | --- |
| Overwriting RStudio | Own folder, executable, uninstaller, shortcut and uninstall key; the installer's running-app check looks for `SuperR.exe` only |
| File associations | Only offered: `OpenWithProgids` / `OpenWithList` entries and `SuperR.*` ProgIDs. The default program of `.R`, `.Rproj`, `.Rmd`, `.qmd`, `.RData` … is never written. Upstream's `RStudio.*` ProgIDs are not created or deleted (`package/win32/superr-registry.cmake` replaces upstream's lists) |
| Preferences and session state | The packaged app sets `RSTUDIO_CONFIG_HOME=%APPDATA%\SuperR` and `RSTUDIO_DATA_HOME=%LOCALAPPDATA%\SuperR` at start-up unless the user set them (`superr-identity.ts`); the session inherits them. RStudio's `%APPDATA%\RStudio` and `%LOCALAPPDATA%\RStudio` are not read or written. Electron's own data goes to `%APPDATA%\SuperR` because its product name is SuperR |
| Single-instance lock, taskbar | Electron keys both on the application's name and user data folder, both SuperR. No explicit AppUserModelID is set, so the Start Menu shortcut and the window share the executable-derived identity |
| R | Discovered as RStudio does: registry, `PATH`, `RSTUDIO_WHICH_R`. SuperR never installs or updates packages by itself |
| Updates | The update check against Posit's servers is compiled out (`RSTUDIO_DISABLE_CHECK_FOR_UPDATES`); *Check for Updates* is removed from the menu |
| Uninstall | Removes the install folder, shortcut and SuperR's registry entries only. User settings in `%APPDATA%\SuperR` / `%LOCALAPPDATA%\SuperR`, projects, scripts, data and R libraries are kept |

The SuperR features are on in the packaged app. `SUPER_RSTUDIO_EXPERIMENTAL=0`
in the environment starts it without them, as plain RStudio functionality.

## Signing

The installer and executables are **not signed**: there is no code-signing
certificate for SuperR. Windows SmartScreen will warn ("Windows protected your
PC", unknown publisher) on download and first run. Do not disable Defender or
SmartScreen. The integrity of a download can be checked against the published
SHA-256 file:

```powershell
(Get-FileHash .\SuperR-0.1.0-preview.1-Windows-x64.exe -Algorithm SHA256).Hash
```

Authenticode signing needs an OV or EV certificate issued to the publisher,
or a cloud signing service (e.g. Azure Trusted Signing) whose identity
validation the owner completes. Once that exists, `signtool sign /fd sha256
/tr <timestamp URL> /td sha256` runs on `SuperR.exe`, the session binaries and
the installer before `cpack`, as upstream's Jenkins pipeline does.

## Windows 10

The build uses Electron 43 and the same runtime as upstream RStudio 2026.10.
Whether that combination still supports Windows 10 has not been checked.
SuperR has **only been tested on Windows 11** (see the checklist). Windows 10
stays unverified until `test-packaged.ps1` passes on a Windows 10 x64 machine.
