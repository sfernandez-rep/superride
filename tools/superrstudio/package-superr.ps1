<#
.SYNOPSIS
   Builds the SuperR Windows x64 installer (optimised package build + NSIS).
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   The upstream package path (package\win32\make-package.bat) with the
   SuperR identity from package\superr\product.json and this repository's
   pinned toolchain (enter-windows.cmd):

     1. configure build\superr-package once: Ninja, RelWithDebInfo (optimised,
        as upstream release builds), RSTUDIO_PACKAGE_BUILD=1, GWT compiled in
        optimised mode for the desktop module, update checks against Posit
        disabled (RSTUDIO_DISABLE_CHECK_FOR_UPDATES)
     2. build everything (session, GWT client, Electron desktop as SuperR.exe)
     3. add the file-type icon groups to SuperR.exe, as make-package.bat does
     4. run CPack/NSIS and copy the installer and its SHA-256 file to
        dist\superr\ together with a provenance record (commit, versions,
        toolchain)

   Nothing is installed and no RStudio installation is touched. The output is
   not signed. dist\ is ignored by Git.

.EXAMPLE
   tools\superrstudio\package-superr.ps1
   tools\superrstudio\package-superr.ps1 -Quick      # build only, no installer
   tools\superrstudio\package-superr.ps1 -Reconfigure
#>
[CmdletBinding()]
param(
   [string]$BuildDir,
   [switch]$Reconfigure,
   # Build and stage only; do not run CPack.
   [switch]$Quick,
   [int]$Parallel = [Math]::Max(2, [Environment]::ProcessorCount - 2)
)

. (Join-Path $PSScriptRoot 'dev-common.ps1')
if (-not $BuildDir) { $BuildDir = Join-Path $SrsRoot 'build\superr-package' }
$product = Get-Content (Join-Path $SrsRoot 'package\superr\product.json') -Raw | ConvertFrom-Json
$displayVersion = "$($product.version)-$($product.prerelease)"

# The RStudio version the build reports to R packages (rstudioapi) stays the
# upstream release it is based on; the suffix marks it as a preview build.
if ($product.upstream.version -notmatch '^(\d+)\.(\d+)\.(\d+)\+(\d+)$')
{
   throw "Unexpected upstream version '$($product.upstream.version)' in product.json."
}
$env:RSTUDIO_VERSION_MAJOR = $Matches[1]
$env:RSTUDIO_VERSION_MINOR = $Matches[2]
$env:RSTUDIO_VERSION_PATCH = $Matches[3]
$env:RSTUDIO_VERSION_SUFFIX = "-preview+$($Matches[4])"
$env:GWT_MAIN_MODULE = 'RStudioDesktop'
$buildType = 'RelWithDebInfo'

$started = Get-Date
if ($Reconfigure -or -not (Test-Path (Join-Path $BuildDir 'build.ninja')))
{
   Write-SrsStep "Configuring $BuildDir (package build)"
   $configure = "cmake -S `"$SrsRoot`" -B `"$BuildDir`" -G Ninja -DCMAKE_BUILD_TYPE=$buildType " +
                "-DCMAKE_C_COMPILER=cl.exe -DCMAKE_CXX_COMPILER=cl.exe -DRSTUDIO_TARGET=Electron " +
                "-DRSTUDIO_PACKAGE_BUILD=1 -DLIBR_HOME=C:\R\R-3.6.3 -DGWT_BUILD=1 " +
                "-DRSTUDIO_DISABLE_CHECK_FOR_UPDATES=1"
   $code = Invoke-SrsBuildEnv $configure
   if ($code -ne 0) { throw "CMake configuration failed (exit $code)." }
}

# The package build compiles the client into src\gwt\www, where development
# builds put their draft client too: always recompile it optimised, so a
# draft client is never packaged
Remove-Item (Join-Path $BuildDir 'src\gwt\timestamp') -ErrorAction SilentlyContinue
Write-SrsStep 'Building (session, optimised GWT client, Electron desktop)'
$code = Invoke-SrsBuildEnv "cmake --build `"$BuildDir`" --parallel $Parallel"
if ($code -ne 0) { throw "Package build failed (exit $code)." }

# file-type icons referenced by the installer's ProgIDs (SuperR.exe,-2 ...)
$desktopOut = Join-Path $SrsRoot "src\node\desktop-build-AMD64\out\$($product.productName)-win32-x64"
$exe = Join-Path $desktopOut "$($product.executableName).exe"
if (-not (Test-Path $exe)) { throw "The desktop build did not produce $exe." }
$rezh = Join-Path (Split-Path $SrsRoot -Parent) 'rstudio-tools\dependencies\windows\resource-hacker\ResourceHacker.exe'
if ($env:RSTUDIO_TOOLS_ROOT) { $rezh = Join-Path $env:RSTUDIO_TOOLS_ROOT 'dependencies\windows\resource-hacker\ResourceHacker.exe' }
if (-not (Test-Path $rezh)) { throw "ResourceHacker.exe not found at $rezh." }
$icons = 'RProject', 'RSource', 'CSS', 'HTML', 'JS', 'Markdown', 'QuartoMarkdown', 'RData', 'RDoc',
         'RHTML', 'RMarkdown', 'RPresentation', 'RSweave', 'RTex'
for ($i = 0; $i -lt $icons.Count; $i++)
{
   $ico = Join-Path $SrsRoot "src\node\desktop\resources\icons\$($icons[$i]).ico"
   & $rezh -open $exe -save $exe -action addoverwrite -resource $ico -mask "ICONGROUP,$($i + 2),1033" | Out-Null
   if ($LASTEXITCODE -ne 0) { throw "ResourceHacker failed for $($icons[$i]).ico." }
}
Write-SrsStep 'File-type icons added to the executable'

if ($Quick)
{
   Write-SrsStep ("Build finished in {0:n0} min (no installer, -Quick)" -f ((Get-Date) - $started).TotalMinutes)
   return
}

# CPack stages under C:\rsbuild (package\win32\CMakeLists.txt) to keep
# installer paths short; remove the previous staging tree first
$stage = 'C:\rsbuild\_CPack_Packages'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
Write-SrsStep 'Creating the NSIS installer'
$code = Invoke-SrsBuildEnv "cd /d `"$BuildDir`" && cpack -C $buildType -G NSIS"
if ($code -ne 0)
{
   $log = 'C:\rsbuild\_CPack_Packages\win64\NSIS\NSISOutput.log'
   if (Test-Path $log) { Get-Content $log -Tail 40 | Out-Host }
   throw "CPack/NSIS failed (exit $code)."
}

$name = "$($product.productName)-$displayVersion-Windows-x64.exe"
$installer = Join-Path 'C:\rsbuild' $name
if (-not (Test-Path $installer)) { throw "Installer not found at $installer." }
$dist = Join-Path $SrsRoot 'dist\superr'
New-Item -ItemType Directory -Force $dist | Out-Null
Move-Item -Force $installer (Join-Path $dist $name)
$hash = (Get-FileHash (Join-Path $dist $name) -Algorithm SHA256).Hash.ToLower()
Set-Content -Path (Join-Path $dist "$name.sha256") -Value "$hash  $name" -Encoding ascii

$commit = (git -C $SrsRoot rev-parse HEAD).Trim()
$dirty = [bool](git -C $SrsRoot status --porcelain --untracked-files=no)
$provenance = [ordered]@{
   product = $product.productName
   version = $displayVersion
   installer = $name
   sha256 = $hash
   commit = $commit
   working_tree_modified = $dirty
   upstream_base = $product.upstream.version
   rstudio_version_reported = "$env:RSTUDIO_VERSION_MAJOR.$env:RSTUDIO_VERSION_MINOR.$env:RSTUDIO_VERSION_PATCH$env:RSTUDIO_VERSION_SUFFIX"
   build_type = $buildType
   gwt = 'optimised (gwtc), module RStudioDesktop'
   update_check = 'disabled (RSTUDIO_DISABLE_CHECK_FOR_UPDATES)'
   signed = $false
   built_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
   build_host_os = (Get-CimInstance Win32_OperatingSystem).Caption
}
$provenance | ConvertTo-Json | Set-Content -Path (Join-Path $dist "$name.provenance.json") -Encoding utf8
if ($dirty) { Write-Warning 'The working tree had uncommitted changes; the provenance records this.' }
Write-SrsStep ("Installer: {0} ({1:n1} MB, sha256 {2})" -f (Join-Path $dist $name), ((Get-Item (Join-Path $dist $name)).Length / 1MB), $hash)
Write-SrsStep ("Finished in {0:n0} min" -f ((Get-Date) - $started).TotalMinutes)
