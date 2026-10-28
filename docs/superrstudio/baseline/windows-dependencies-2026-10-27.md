# Windows dependency provisioning

The user authorized installation of dependencies on 2026-10-27. The process
started from a non-elevated console, then used Windows UAC to launch signed
installers with administrator rights. Existing VS 2022 and Oracle Java 21
installations were retained. Validation and the baseline build continued on
2026-10-28 (America/Montevideo).

## Installed and verified host prerequisites

| Component | Installed version / location |
| --- | --- |
| Visual Studio 2026 Build Tools | Bootstrapper 18.7.3; installed build 18.7.11925.98 |
| MSVC | Tools directory 14.51.36231, compiler 19.51.36248.0, toolset 145, x86/x64 |
| Windows SDK | 10.0.26100.0 |
| CMake | Portable 4.3.4, `.cache/superrstudio/tools/` |
| Ninja | Portable 1.13.1, same tools root |
| Eclipse Temurin JDK 17 | 17.0.20.1+1, `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot` |
| Apache Ant | 1.10.18, user Scoop installation |
| Strawberry Perl | 5.42.3.1 installer, Perl v5.42.3, `C:\Strawberry` |
| Python | 3.13.15, user installation under `AppData\Local\Programs\Python\Python313` |
| NSIS | 3.12, `C:\Program Files (x86)\NSIS` |
| jq | 1.8.2, user Scoop installation |
| Build R | 3.6.3, `C:\R\R-3.6.3` |
| Runtime/test R | 4.6.1, `C:\R\R-4.6.1` |

Visual Studio, R installers and package-manager downloads were signature/hash
validated. The VS bootstrapper SHA-256 was
`07b09afd416dc05c781f171c881c23e42907eeb8d812fa1d2993dffb9323c869`.
CMake 4.3.4 SHA-256 is
`86e5fcafb38bdf58346a78b187c7b6b4f252ae5242cffe24c463a92bbd2e77d1`.
All native prerequisite installers completed with exit 0. Windows long-path
support was verified enabled. Ant and jq were installed through Scoop; the main
and java buckets were added and Scoop updated itself during installation.

A Chocolatey installer download was rejected by the environment's automatic
policy review. Installation continued through existing Winget/Scoop and official
signed installers; Chocolatey was not installed.

## Build environment corrections

CMake 3.31.10 maps any MSVC >= 1930 to toolset 143, which is incompatible with
this release's required toolset 145. CMake 4.3.4 explicitly maps MSVC >= 1950 to
145. Its official source and archive digest were checked before upgrading the
portable bootstrap. The old portable version was retained in the ignored cache.
Upstream application/build source was not modified to bypass the toolset guard.

The [environment helper](../../../tools/superrstudio/enter-windows.cmd) configures
one Command Prompt process. It selects JDK 17, the pinned CMake/Ninja and Node
build location, the SDK and MSVC developer environment. `LIBR_HOME` defaults to
the legacy build R, while `RSTUDIO_WHICH_R` selects R 4.6.1 for the desktop.
Existing explicit overrides for the tools root, R locations and SDK are honored.

The helper clears only inherited `C.UTF-8` values for LANG/LC_ALL/LC_CTYPE in
that shell, because native Windows R and Perl reject that MSYS locale. With
the correction, R 4.6.1 uses `Spanish_Uruguay.utf8`, and R 3.6.3 uses the native
1252 locale, without startup warnings. Global locale settings were not changed.

From a fresh Command Prompt in the fork:

```bat
call tools\superrstudio\enter-windows.cmd
```

For a clean host, use Winget to install the four packages below (elevation is
required for machine installers), Scoop for Ant/jq, and the signed upstream R
installers for the exact build/runtime versions:

```powershell
winget install --id EclipseAdoptium.Temurin.17.JDK --version 17.0.20.101 --exact --source winget
winget install --id StrawberryPerl.StrawberryPerl --version 5.42.3.1 --exact --source winget
winget install --id Python.Python.3.13 --version 3.13.15 --exact --source winget
winget install --id NSIS.NSIS --version 3.12 --exact --source winget
scoop install ant jq
```

The Visual Studio bootstrapper URL and required components remain those in the
pinned upstream `dependencies/windows/Install-RStudio-Prereqs.ps1`. Its all-in-one
Chocolatey bootstrap was not run. The installed workload is VCTools plus VC
x86/x64 tools and Windows11SDK.26100; ARM64 tools were not requested.

## Verification performed

- A standalone program compiled with MSVC `/std:c++20 /EHsc`, included Windows.h
  and the STL, linked and executed successfully.
- The environment helper resolved CMake 4.3.4, Ninja 1.13.1, Java 17, Ant, Python
  3.13.15, Perl 5.42.3 and NSIS 3.12; verification exited 0.
- The existing standalone R reference fixture passed **locally on Windows 11**
  with both R 4.6.1 and R 3.6.3: CSV/TSV, missing values/types, derived data,
  analytic linear regression and PDF export. These do not exercise RStudio.
- The updated portable bootstrap ran successfully against verified cached files.

Small evidence logs: [environment verification](windows-environment-verified.log)
and [successful CMake configure](windows-configure-provisioned.log).

Raw installer/build logs are under `.cache/superrstudio/` and Windows installer
temporary logs. No research datasets, renv environments or optional scientific
packages were installed or changed by these checks.

## Upstream dependency and baseline assessment

A pristine detached worktree was created at `D:\Git\SuperRStudio-baseline`,
commit `e961c6137d92315437caf5af53959f7110b517f9`. Its upstream Windows dependency
installer completed with exit **0**, using external destination
`D:\Git\rstudio-tools`, whose resolved path was checked before installation.

Node 22.22.2 (build), Node 24.21.0 (bundled) and Quarto 1.10.18 were executed and
matched the upstream pins. GWT, Pandoc 3.2, libclang 13.0.1, OpenSSL 3.1.4, Boost
1.91.0 and NSIS plugins were installed. SOCI 4.0.3/SQLite compiled successfully
for x86/x64 Debug/Release; all eight required SOCI core/SQLite static libraries
were checked. An artifact audit verified 16 required files, including both GWT
jars and Boost's CMake package. An initial audit used an incorrect version-folder
guess for GWT; checking `build.xml` and the extracted archive resolved the actual
`gwtproject/gwt/gwt-rstudio/` layout without changing upstream code.

The panmirror checkout is the declared `release/rstudio-blue-mistflower` branch
of quarto-dev/quarto at `2d5a23d918079ce38f584a31b4639aa769379d64`.
The localization helper's isolated Python 3.13 virtual environment installed
pytest 9.2.0 and lxml 6.1.3 with their dependencies.

Fresh baseline configuration completed with exit **0** in 66.5 seconds:

```bat
call D:\Git\SuperRStudio\tools\superrstudio\enter-windows.cmd
cd /d D:\Git\SuperRStudio-baseline
cmake -S . -B build\baseline-windows -G Ninja -DRSTUDIO_TARGET=Electron -DCMAKE_BUILD_TYPE=RelWithDebInfo -DLIBR_HOME=C:\R\R-3.6.3
cmake --build build\baseline-windows --parallel 4
```

CMake identified MSVC 19.51.36248.0/toolset 145, R 3.6.3 and the pinned Node
tools, fetched upstream's remaining C++ libraries and generated `build.ninja`.
The full build is under assessment. No RStudio startup success is claimed by
the host-tool, artifact or configure checks. The detached worktree's tracked
source was confirmed unchanged after dependency installation and configuration.

## Fork changes

Updated the portable CMake pin, added the Command Prompt environment helper and
recorded current setup/build status in README, BUILDING, COMPATIBILITY, ROADMAP,
UPSTREAM and AGENTS. Added this report and the two small evidence logs. No
upstream application/build source or licensing files changed. Full application
startup and regression testing remain the next gate after a successful build.
