# SuperRStudio development helpers shared by dev-*.ps1. SPDX-License-Identifier: AGPL-3.0-only
# Dot-source this file; it defines paths and functions only and changes nothing.

$ErrorActionPreference = 'Stop'

$script:SrsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:SrsCache = Join-Path $SrsRoot '.cache\superrstudio'
$script:SrsBuildDir = Join-Path $SrsRoot 'build\superrstudio-windows'
$script:SrsEnterCmd = Join-Path $PSScriptRoot 'enter-windows.cmd'
$script:SrsGwtXml = Join-Path $PSScriptRoot 'gwt-dev.xml'
$script:SrsStampDir = Join-Path $SrsCache 'dev'
$script:SrsProfilesDir = Join-Path $SrsCache 'dev-profiles'
$script:SrsBaseline = if ($env:SUPER_RSTUDIO_BASELINE) { $env:SUPER_RSTUDIO_BASELINE } else { Join-Path (Split-Path $SrsRoot -Parent) 'SuperRStudio-baseline' }

# Native targets the development desktop needs (session, helpers, diagnostics).
$script:SrsNativeTargets = @('rsession', 'rsession-utf8', 'rpostback', 'consoleio', 'diagnostics')

function Write-SrsStep([string]$Message)
{
   Write-Host "[superrstudio] $Message" -ForegroundColor Cyan
}

# Run a cmd.exe command line after configuring the pinned Windows toolchain
# (enter-windows.cmd only affects that child shell). Returns the exit code.
function Invoke-SrsBuildEnv([string]$CommandLine)
{
   $full = "call `"$SrsEnterCmd`" >nul && $CommandLine"
   & cmd.exe /d /s /c "`"$full`"" | Out-Host
   return $LASTEXITCODE
}

# The desktop (Electron main/renderer) build. Desktop TypeScript is unchanged
# in this fork so far, so the pristine baseline's verified build is reused
# unless this checkout has built its own.
function Get-SrsDesktopDir
{
   foreach ($candidate in @((Join-Path $SrsRoot 'src\node\desktop-build-amd64'),
                            (Join-Path $SrsBaseline 'src\node\desktop-build-amd64')))
   {
      if (Test-Path (Join-Path $candidate '.webpack\x64\main\index.js')) { return $candidate }
   }
   throw "No built Electron desktop found (.webpack\x64\main\index.js). Build src/node/desktop or set SUPER_RSTUDIO_BASELINE."
}

function Get-SrsElectronExe([string]$DesktopDir)
{
   foreach ($candidate in @((Join-Path $SrsCache 'electron-runtime\electron.exe'),
                            (Join-Path $DesktopDir 'node_modules\electron\dist\electron.exe')))
   {
      if (Test-Path $candidate) { return $candidate }
   }
   throw "No Electron runtime found; see docs/superrstudio/baseline/windows-gui-2026-10-28.md."
}

# Newest write time of any file below the given directories (for build stamps).
function Get-SrsNewestWrite([string[]]$Paths)
{
   $newest = [datetime]::MinValue
   foreach ($path in $Paths)
   {
      if (-not (Test-Path $path)) { continue }
      foreach ($file in [System.IO.Directory]::EnumerateFiles($path, '*', 'AllDirectories'))
      {
         $time = [System.IO.File]::GetLastWriteTimeUtc($file)
         if ($time -gt $newest) { $newest = $time }
      }
   }
   return $newest
}
