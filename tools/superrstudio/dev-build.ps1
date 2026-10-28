<#
.SYNOPSIS
   Incremental SuperRStudio development build (native session + GWT client).
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   Native: configures build\superrstudio-windows once (Ninja, RelWithDebInfo,
   GWT_BUILD=OFF) and then only runs Ninja for the session targets, so
   unchanged sources are not recompiled.
   GWT: runs the upstream `ant draft` through tools\superrstudio\gwt-dev.xml,
   skipped when nothing under src\gwt changed since the last successful build.
   Nothing is installed; the official RStudio installation is not touched.

.EXAMPLE
   tools\superrstudio\dev-build.ps1                  # native + GWT, incremental
   tools\superrstudio\dev-build.ps1 -Component native
   tools\superrstudio\dev-build.ps1 -Component gwt -Force
   tools\superrstudio\dev-build.ps1 -Component javac  # fast Java compile check only
#>
[CmdletBinding()]
param(
   [ValidateSet('all', 'native', 'gwt', 'javac')]
   [string]$Component = 'all',
   # Re-run CMake configuration even if build.ninja exists.
   [switch]$Reconfigure,
   # Rebuild GWT even when no client source changed.
   [switch]$Force,
   [int]$Parallel = [Math]::Max(2, [Environment]::ProcessorCount - 2)
)

. (Join-Path $PSScriptRoot 'dev-common.ps1')
New-Item -ItemType Directory -Force $SrsStampDir | Out-Null

function Build-Native
{
   if ($Reconfigure -or -not (Test-Path (Join-Path $SrsBuildDir 'build.ninja')))
   {
      Write-SrsStep "Configuring $SrsBuildDir"
      $configure = "cmake -S `"$SrsRoot`" -B `"$SrsBuildDir`" -G Ninja -DRSTUDIO_TARGET=Electron " +
                   "-DCMAKE_BUILD_TYPE=RelWithDebInfo -DLIBR_HOME=C:\R\R-3.6.3 -DGWT_BUILD=OFF"
      $code = Invoke-SrsBuildEnv $configure
      if ($code -ne 0) { throw "CMake configuration failed (exit $code)." }
   }

   Write-SrsStep "Native build: $($SrsNativeTargets -join ', ')"
   $started = Get-Date
   $code = Invoke-SrsBuildEnv "cmake --build `"$SrsBuildDir`" --parallel $Parallel --target $($SrsNativeTargets -join ' ')"
   if ($code -ne 0) { throw "Native build failed (exit $code). See the compiler errors above." }
   Write-SrsStep ("Native build OK in {0:n0}s" -f ((Get-Date) - $started).TotalSeconds)
}

function Invoke-Ant([string]$Target)
{
   $antArgs = "-f `"$SrsGwtXml`" -Dsuperrstudio.panmirror.source=`"$SrsBaseline\src\gwt\www\js\panmirror`""
   # The i18n helper venv only exists in the baseline worktree; ant only uses
   # it when Commands.cmd.xml changed.
   $python = Join-Path $SrsBaseline 'src\gwt\tools\i18n-helpers\VENV\Scripts\python.exe'
   if (Test-Path $python) { $antArgs += " -Dpython.bin=`"$python`"" }
   return Invoke-SrsBuildEnv "cd /d `"$SrsRoot\src\gwt`" && ant $antArgs $Target"
}

function Build-Gwt
{
   $stamp = Join-Path $SrsStampDir 'gwt-draft.stamp'
   $inputs = @("$SrsRoot\src\gwt\src", "$SrsRoot\src\gwt\acesupport")
   $output = Join-Path $SrsRoot 'src\gwt\www\rstudio\rstudio.nocache.js'
   if (-not $Force -and (Test-Path $stamp) -and (Test-Path $output))
   {
      $built = (Get-Item $stamp).LastWriteTimeUtc
      $newest = Get-SrsNewestWrite $inputs
      foreach ($file in @($SrsGwtXml, "$SrsRoot\src\gwt\build.xml"))
      {
         $time = (Get-Item $file).LastWriteTimeUtc
         if ($time -gt $newest) { $newest = $time }
      }
      if ($newest -le $built)
      {
         Write-SrsStep 'GWT client unchanged since last draft build; skipping (use -Force to rebuild).'
         return
      }
   }

   Write-SrsStep 'GWT draft compile (about 2 minutes)'
   $started = Get-Date
   $code = Invoke-Ant 'draft'
   if ($code -ne 0) { throw "GWT build failed (exit $code). See the javac/GWT errors above." }
   Set-Content -Path $stamp -Value (Get-Date -Format o) -Encoding ascii
   Write-SrsStep ("GWT build OK in {0:n0}s" -f ((Get-Date) - $started).TotalSeconds)
}

switch ($Component)
{
   'native' { Build-Native }
   'gwt'    { Build-Gwt }
   'javac'
   {
      Write-SrsStep 'Java compile check (no JavaScript produced)'
      $code = Invoke-Ant 'javac'
      if ($code -ne 0) { throw "Java compilation failed (exit $code)." }
   }
   default  { Build-Native; Build-Gwt }
}
