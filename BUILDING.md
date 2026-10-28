# Building SuperRStudio

The source pin is in [UPSTREAM.md](UPSTREAM.md). Follow upstream [INSTALL](INSTALL),
[Windows instructions](dependencies/windows/README.md) and
[packaging instructions](package/README.md). The steps below supplement them;
they do not change upstream build requirements.

## Current provisioning update

The Windows host prerequisites are now installed and verified, including VS 2026,
MSVC 145, SDK 26100, Java 17 and both R runtimes. The unmodified native, GWT and
Electron build completed successfully on Windows 11; R-session suites passed
on both R versions, and the desktop GUI acceptance passed
([record](docs/superrstudio/baseline/windows-gui-2026-10-28.md)). See the
[dependency provisioning record](docs/superrstudio/baseline/windows-dependencies-2026-10-27.md)
for actual versions, checks and the current baseline assessment. From Command
Prompt, call `tools\superrstudio\enter-windows.cmd` before building.

The portable bootstrap now installs **CMake 4.3.4**, because 3.31.10 does not
recognize the required MSVC 145 toolset. The initial inventory and failure below
are retained as historical evidence.

## SuperRStudio development mode (Windows)

Edit, build incrementally and run the desktop from this checkout without
producing or installing a release. The scripts live in `tools/superrstudio/`,
run from any PowerShell (they configure the pinned toolchain in a child
`cmd.exe` via `enter-windows.cmd`) and stop with a non-zero exit code and the
compiler output on failure. All were executed on 2026-10-28.

| Command | What it does |
| --- | --- |
| `dev-build.ps1` | Native session targets (`rsession`, `rsession-utf8`, `rpostback`, `consoleio`, `diagnostics`) with Ninja in `build\superrstudio-windows`, configured once (RelWithDebInfo, `GWT_BUILD=OFF`); then the GWT client with upstream `ant draft`. A no-op native build takes about 2 s; GWT is skipped when nothing under `src\gwt\src` or `acesupport` changed since the last successful draft (about 75 s otherwise). `-Component native\|gwt\|javac`, `-Force`, `-Reconfigure`. |
| `dev-run.ps1` | Starts Electron with `RSTUDIO_CPP_BUILD_OUTPUT=build\superrstudio-windows`, so `rdesktop-dev.conf` serves the GWT client from `src\gwt\www` and session R modules from this checkout. `-Experimental` sets `SUPER_RSTUDIO_EXPERIMENTAL=1` for the session only. `-Wait` stays attached and returns the IDE's exit code. |
| `dev.ps1` | `dev-build.ps1`, then `dev-run.ps1` with the same run options (`-NoBuild` to skip). |
| `dev-clean.ps1` | Explicit, `-WhatIf`-capable cleanup: `-ProfileName a,b` / `-AllProfiles`, `-Gwt` (upstream `ant clean`), `-Native` (Ninja clean; configuration kept, next build is a full ~20 min compile). Refuses running profiles and path-like names. |
| `install-vscode.ps1` | Merges `.vscode/superrstudio/{tasks,launch}.json` into the Git-ignored `.vscode/tasks.json` and `launch.json` (created from upstream's `.vscode/open-source/` templates if missing). Idempotent; keeps `*.bak`. |

```powershell
tools\superrstudio\dev.ps1 -Experimental          # build what changed, launch with SuperRStudio features
tools\superrstudio\dev-run.ps1 -Experimental      # relaunch without building
tools\superrstudio\dev-build.ps1 -Component gwt   # after Java-only edits
tools\superrstudio\dev-build.ps1 -Component javac # fastest Java compile check (no JavaScript)
```

After Java/GWT-only changes a restart is unnecessary: rebuild GWT and use
*Help > Diagnostics > Reload UI* (the R session keeps its state). C++ and
session R module changes need a restart, because modules are initialized and
sourced when the session starts.

**Isolation.** Each run uses `.cache\superrstudio\dev-profiles\<ProfileName>`
(default `default`) for RStudio config/state/data, Electron user data, `HOME`
and the working directory, with `R_PROFILE_USER`/`R_ENVIRON_USER` disabled. The
session's user library is `.cache\superrstudio\r-library` (holds ggplot2 4.0.3)
unless `-RLibrary DIR` is given. Your normal RStudio settings, any installed
RStudio and other R libraries are neither read for preferences nor modified.
Environment variables are set for the child process only.

**Reuse.** The Electron main/renderer build is taken from
`src\node\desktop-build-amd64` if built here, otherwise from the verified
baseline worktree (`..\SuperRStudio-baseline`, override with
`SUPER_RSTUDIO_BASELINE`), because desktop TypeScript is not modified yet. The
Electron runtime is `.cache\superrstudio\electron-runtime\electron.exe`. The
panmirror (visual editor) bundle is reused through `tools/superrstudio/gwt-dev.xml`
instead of rebuilding it with yarn on every GWT build. Electron is started with
`.` from the webpack main directory, as upstream's dev start does; passing the
script path made RStudio open `index.js` as a document.

**Debugging.** `-DebugPort 9222` exposes the GWT client to Chrome DevTools /
Playwright (`http://127.0.0.1:9222`), `-InspectPort 9229` the Electron main
process to a Node debugger, `-Automation` installs the `window.rstudio`
automation bridge. Native code is RelWithDebInfo; attach Visual Studio or the
VS Code `cppvsdbg` configuration to `rsession.exe`. Logs: the paths printed at
launch (`desktop.out.log`, `desktop.err.log`, `data-home\log`).
`node tools\superrstudio\dev-quit.cjs PORT` quits a desktop started with a debug
port through RStudio itself (quitSession, or closing the window).

**VS Code.** After `tools\superrstudio\install-vscode.ps1`, *Run Build Task*
(Ctrl+Shift+B) offers `SuperRStudio: Build (incremental)`; other tasks run the
desktop (experimental or standard), build and run, run the tests or clean
profiles. Debug configurations: *Launch and attach to Electron main* (starts the
desktop with both debug ports), *Attach to GWT client* and *Attach to rsession
(C++)*. They are `process` tasks, so they do not depend on the upstream
template's `vcvarsall.bat` shell wrapper. If upstream's `RStudio: Build All` is
also marked default, VS Code asks which build task to run.

**Tests.**

```powershell
Rscript tests\superrstudio\visual-scatter.R            # R contract (set R_LIBS_USER to the isolated library for ggplot2)
tools\superrstudio\test-session.cmd experimental        # upstream rsession --run-tests on the feature build
tools\superrstudio\test-gui-scatter.ps1                 # live desktop: ggplot2, no-ggplot2, disabled
```

The GUI test needs the Playwright client in `.cache\superrstudio\ui-client`
(see the GUI acceptance record) and a free port 19381.

Known limitation: when a non-interactive tool runs `dev-run.ps1` without
`-Wait`, that tool's output pipe stays open until the desktop exits, because the
child inherits the console handles. Interactive shells and VS Code tasks are
unaffected; automation should run the launcher in the background.

## Observed environment, 2026-10-27

Windows 11 Pro for Workstations x64, version `10.0.26300`; non-administrator
session. Git 2.48.1.windows.1, authenticated GitHub CLI 2.96.0, Oracle JDK/javac
21.0.7, MSYS2 Python 3.11.9 and 7-Zip 24.09 are present. MSYS2 MinGW GCC/G++
14.2.0 is installed, but upstream's Windows build requires MSVC. VS 2022 Build
Tools 17.14.36518.9 and
Community 17.10.35122.118 are installed **without** the VC++ workload. `vswhere`
finds no C++ toolset. No Windows R, Node/npm, Ant, Quarto or SDK was located in
PATH or the inspected standard locations. This inventory is not a whole-disk scan.

Portable CMake **3.31.10** and Ninja **1.13.1** were downloaded from their official
GitHub releases, SHA-256 verified and run under `.cache/superrstudio/tools/`.
[tools/superrstudio/bootstrap-tools.ps1](tools/superrstudio/bootstrap-tools.ps1)
now provides the compatible CMake 4.3.4 replacement without administrator rights
or persistent PATH changes.

WSL Ubuntu 24.04.3 is available with GCC 13.3.0 and Python 3.12.3. It has no
CMake, Node or R on PATH; `sudo -n true` requests a password. No sudo password
was requested and no WSL system packages were installed.

## Source-discovered requirements

| Component | Requirement or pin | Authority in this checkout |
| --- | --- | --- |
| CMake / generator | >= 3.25, Ninja on Windows | `CMakeLists.txt`, `INSTALL` |
| Windows C++ | MSVC toolset **145**, VS 2026; C++20 | `cmake/windows-checks.cmake`, `cmake/compiler.cmake` |
| VS installer / SDK | VS Build Tools **18.7.3**, Windows11SDK.26100 | `dependencies/windows/Install-RStudio-Prereqs.ps1` |
| Linux C++ | C++17; native development libraries | `cmake/compiler.cmake`, `dependencies/linux/install-dependencies-noble` |
| Java / GWT | Java 17 target, Ant, GWT 2.12.2-autumn-hawkbit | `src/gwt/build.xml`, Windows dependency script |
| Node | 22.22.2 for build, 24.21.0 bundled | `dependencies/tools/rstudio-tools.cmd`, `cmake/globals.cmake` |
| Electron / TypeScript | 43.7.7 / 6.0.3 | `src/node/desktop/package.json` |
| Boost / SOCI | 1.91.0 / 4.0.3; Boost msvc145 archive, SOCI built with MSVC 145 | Windows install scripts, `install-soci/install-soci.R` |
| Other Windows dependencies | OpenSSL 3.1.4, libclang 13.0.1, Pandoc 3.2, Quarto 1.10.18, NSIS and plugins | `dependencies/windows/install-dependencies.cmd` |
| R integration | minimum 3.6.0; maximum-version guard 4.6.1; CI pin 4.6.1 | `cmake/globals.cmake`, `dependencies/tools/rstudio-tools.sh` |

These are source pins, not statements that every download or version works.
`dependencies/metadata/general.txt` lists Boost 1.87.0 while the active install
script and Linux README require 1.91.0. Preserve and investigate this upstream
inventory discrepancy before packaging. The bootstrap installs R 3.6.3 for build
compatibility; modern scientific packages can require newer R. JDK 21 presence
does not validate the prescribed JDK 17 build path.

## Reproduce an unmodified Windows baseline

Use a separate worktree to avoid changing existing work:

```powershell
git fetch upstream --tags
git worktree add --detach ..\SuperRStudio-baseline v2026.10.0+233
git -C ..\SuperRStudio-baseline rev-parse HEAD
```

The result must be `e961c6137d92315437caf5af53959f7110b517f9`.
In an **Administrator PowerShell**, read and run the checked-out script rather
than downloading a moving `main` script:

```powershell
Set-Location ..\SuperRStudio-baseline\dependencies\windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-RStudio-Prereqs.ps1
```

This installs system-wide tools and requires an elevated process. The current
host was provisioned through UAC with Winget/Scoop and signed installers instead
of the all-in-one Chocolatey bootstrap; see the provisioning record above.
Inspect prerequisite versions first, especially the R 3.6.3 build runtime.
Preserve existing R installations and scientific project libraries.
Open a fresh **non-administrator Command Prompt**, then:

```bat
cd /d D:\Git\SuperRStudio-baseline
set RSTUDIO_TOOLS_ROOT=D:\Git\rstudio-tools
cd dependencies\windows
call install-dependencies.cmd
```

Do not trust only the batch exit code: inspect the output and confirm the
required artifacts exist. The dependency script can emit an error and return an
unhelpful status. Then, from the worktree root in the same Command Prompt:

```bat
call src\cpp\tools\windows-dev.cmd
where cl
where ninja
where cmake
cmake -S . -B build\baseline -G Ninja -DRSTUDIO_TARGET=Electron -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build\baseline
cd src\gwt
ant draft
cd ..\node\desktop
npm ci
set RSTUDIO_CPP_BUILD_OUTPUT=D:\Git\SuperRStudio-baseline\build\baseline
npm start
```

Check each step before proceeding. `src/node/desktop/src/main/utils.ts` supports
`RSTUDIO_CPP_BUILD_OUTPUT` and searches both `session/` and `src/cpp/session/`
beneath it. The explicit path above avoids picking another build directory.
Upstream also documents a separate development layout (`src\build` configured
from `src\cpp`). A root CMake build alone is not proof the desktop can launch.
For a staged installer, use the upstream package path instead:

```bat
set RSTUDIO_VERSION_MAJOR=2026
set RSTUDIO_VERSION_MINOR=10
set RSTUDIO_VERSION_PATCH=0
set RSTUDIO_VERSION_SUFFIX=-superrstudio-dev+233
cd package\win32
make-package.bat
```

This is a development suffix, not a release. Audit branding, install paths and
updaters before installing beside an existing RStudio installation. Inspect the
packaging log for the actual artifact path. No artifact has been produced here.

## Initial local build result

Before any tracked changes, `git diff --quiet` returned 0. Upstream
`windows-dev.cmd` reported no Visual Studio C++ installation and could not run
`VsDevCmd.bat`. Portable CMake was then invoked with the required compiler:

```powershell
cmake -S . -B build\baseline-windows -G Ninja -DRSTUDIO_TARGET=Electron -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_CXX_COMPILER=cl -DCMAKE_C_COMPILER=cl
cmake --build build\baseline-windows
```

Configure exited **1** at `CMakeLists.txt:25`: `cl` was not found. Build exited
**1** because no `build.ninja` had been generated. No translation units compiled;
startup and R-session smoke tests could not run. See
[baseline evidence](docs/superrstudio/baseline/2026-10-27.md). This is an
environment blocker, not evidence of a SuperRStudio source regression.

## Ubuntu 24.04 strategy

Use a native x64 VM for desktop validation (WSLg does not establish native
desktop compatibility). Use a fresh Linux checkout on the Linux filesystem;
do not reuse this Windows CRLF checkout with Linux Git's different line-ending
configuration. In an unmodified baseline checkout, review and run:

```bash
cd dependencies/linux
./install-dependencies-noble
cd ../..
cmake -S . -B build/baseline -G Ninja -DRSTUDIO_TARGET=Electron -DRSTUDIO_PACKAGE_BUILD=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build/baseline
export RSTUDIO_VERSION_MAJOR=2026 RSTUDIO_VERSION_MINOR=10 RSTUDIO_VERSION_PATCH=0
export RSTUDIO_VERSION_SUFFIX=-superrstudio-dev+233
cd package/linux
./make-package Electron DEB
```

The dependency script uses sudo/apt, installs R development files and native
libraries, then executes `dependencies/common/install-common`. Review the
script and capture versions/checksums; distro packages and some upstream
downloads remain moving inputs. The source pin alone does not make a build
bit-for-bit reproducible. This Linux procedure has not been executed locally.

## Checks and CI

```powershell
python tools/superrstudio/check-baseline.py --pristine
Rscript --vanilla tests/superrstudio/runtime-smoke.R
```

The foundation workflow runs source integrity and a base-R reference fixture on
Windows and Ubuntu. It does **not** compile or start RStudio. Reuse upstream
`os-test-e2e-rstudio-desktop-os-windows-server-2025.yml` and
`os-test-e2e-rstudio-desktop-os-ubuntu-24.yml` for subsequent explicit source-build
validation (`build_from_source=true`, `require_tests_passed=true`); inspect their
runner/tool and optional-secret requirements before dispatch. Daily-binary tests
do not certify this source. No full source-build workflow was dispatched during
initialization.
