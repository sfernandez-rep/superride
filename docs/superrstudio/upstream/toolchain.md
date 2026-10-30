# Updating build dependencies and the toolchain

A new RStudio release can need new versions of Boost, Node, Electron, GWT,
Quarto, Pandoc, OpenSSL, CMake or Visual Studio. Upstream declares them in
its source. SuperR takes them **from upstream's declarations**, installs them
with **upstream's installer**, records what it installed, and updates the
places where SuperR's own scripts repeat a version. The sync assessment lists
the changed toolchain files and their version lines (section "Toolchain and
dependency changes").

## Where upstream declares versions

| File | Declares |
| --- | --- |
| `dependencies/windows/install-dependencies.cmd` | Windows: Boost, GWT, libclang, OpenSSL, Pandoc, Quarto, Copilot language server, SOCI and others |
| `dependencies/tools/rstudio-tools.cmd` | Windows: `RSTUDIO_NODE_VERSION` (build), `RSTUDIO_INSTALLED_NODE_VERSION` (bundled) |
| `cmake/globals.cmake` | The same Node versions and Pandoc for CMake |
| `dependencies/common/install-*`, `dependencies/windows/install-*/` | Per-component versions and download locations (Boost, SOCI, panmirror branch) |
| `src/node/desktop/package.json`, `package-lock.json` | Electron (`"electron"`) and the desktop's npm dependencies |
| `src/gwt/build.xml` | GWT and Java build settings |
| `CMakeLists.txt`, `src/cpp/CMakeLists.txt` | Minimum CMake, compiler and platform checks |
| `version/CALENDAR_VERSION`, `version/PATCH`, `version/RELEASE` | The RStudio version (moves with every release) |
| `version/news/` "Dependencies" sections | Upstream's own list of dependency changes in the release |

Host prerequisites that upstream does not install (Visual Studio Build Tools
and MSVC toolset, Windows SDK, JDK, Ant, Strawberry Perl, Python, NSIS) and
their verified versions are in the
[baseline dependency report](../baseline/windows-dependencies-2026-10-27.md).

## Where SuperR repeats a version

Update these in the same `upstream-sync/*` branch when upstream changes the
corresponding version. Find them with:

```powershell
git grep -n -E "22\.22\.2|24\.21\.0|43\.7\.7|cmake-4\.3\.4|ninja-1\.13\.1|R-3\.6\.3|R-4\.6\.1|r-version" -- tools/superrstudio .github/workflows BUILDING.md
```

(replace the numbers with the old versions).

| Version | SuperR places |
| --- | --- |
| Build Node (`RSTUDIO_NODE_VERSION`) | `-Node` defaults in `test-gui-scatter.ps1`, `test-packaged.ps1`, `bench.ps1`; `BUILDING.md` |
| Electron | `.cache\superrstudio\electron-runtime` (the development runtime, extracted from the build's Electron ZIP; see the [GUI record](../baseline/windows-gui-2026-10-28.md)); `src/node/desktop/scripts/install-fuses.mjs` and `forge.config.js` keep working only if upstream's packaging layout is unchanged (A8) |
| CMake, Ninja (portable) | `tools/superrstudio/bootstrap-tools.ps1` (URL and SHA-256), `tools/superrstudio/enter-windows.cmd` (PATH) |
| R for building / testing | `LIBR_HOME` R 3.6.3 in `enter-windows.cmd`, `dev-build.ps1`, `package-superr.ps1`; R 4.6.1 in `enter-windows.cmd`, `dev-run.ps1`, `test-session.cmd`, `test-gui-scatter.ps1`, `test-packaged.ps1`, `bench.ps1`, `superr-release.yml`, `r-version` in `superr-checks.yml` and `superrstudio-foundation.yml` |
| GitHub Actions | Pinned by commit SHA in `superr-*.yml` and `superrstudio-foundation.yml`; update them deliberately, not with the upstream merge |

The R versions are SuperR's choice, not upstream's. Change them only when
upstream raises its minimum R, or as a separate, tested decision.

## Procedure

1. **Read** the assessment's toolchain section and upstream's release notes
   ("Dependencies"). Note every version that changes.
2. **Host prerequisites.** If upstream needs a newer Visual Studio toolset,
   SDK or JDK, install it next to the current one; don't remove the
   current one until the update is accepted. Record the installer, version
   and checksum.
3. **Upstream dependencies.** Run upstream's installer from the **pristine
   baseline worktree** moved to the new tag, into the shared dependency
   folder, as for the original baseline:

   ```bat
   call D:\Git\SuperRStudio\tools\superrstudio\enter-windows.cmd
   cd /d D:\Git\SuperRStudio-baseline
   git switch --detach v2026.10.1+239
   set "RSTUDIO_TOOLS_ROOT=D:\Git\rstudio-tools"
   dependencies\windows\install-dependencies.cmd
   ```

   Read any changed installer script before running it (it downloads and
   executes tools). Versioned folders (`dependencies\common\node\<version>`)
   install next to the old ones, so the previous baseline still builds and
   rollback needs no reinstallation.
4. **Verify** each new component as in the baseline report (the version
   printed by the executable, the expected files), then rebuild the
   unmodified baseline (`cmake --build build\baseline-windows`): a failure here
   is upstream's or the toolchain's, not SuperR's.
5. **Update SuperR's copies** (table above) on the `upstream-sync/*` branch,
   and refresh `.cache\superrstudio\electron-runtime` when Electron changed.
6. **Record** a new `docs/superrstudio/baseline/windows-dependencies-<date>.md`
   (or a dated section of the current one) with what changed, the commands
   and the verification, and link it from the review record (gate A3) and the
   history entry's `acceptance`.
7. **Security review.** Run `npm audit` in `src/node/desktop` and compare
   with the previous findings ([HANDOFF.md](../../../HANDOFF.md), known
   limitations); upstream's dependency bumps often fix them.

## Upgrading without a new upstream release

SuperR does not upgrade upstream-pinned dependencies on its own. Electron,
Node, Boost and the rest move with upstream's pins, because diverging would
put SuperR's build outside what upstream tests. A security fix that cannot
wait for upstream is a separate `feature/*` change with its own review and
acceptance, recorded as a SuperR modification in `integration-points.json`.
