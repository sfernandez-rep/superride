<#
.SYNOPSIS
   Launch the SuperRStudio development desktop without installing anything.
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   Starts Electron on the built desktop main script with RSTUDIO_CPP_BUILD_OUTPUT
   pointing at build\superrstudio-windows, so the session, GWT client and R
   modules come from this checkout (rdesktop-dev.conf). Settings, state,
   Electron data, HOME and the user R library live in an isolated profile under
   .cache\superrstudio\dev-profiles\<ProfileName>; your normal RStudio settings and
   the installed RStudio are not used or modified.

.EXAMPLE
   tools\superrstudio\dev-run.ps1 -Experimental            # opt-in SuperRStudio features
   tools\superrstudio\dev-run.ps1 -Experimental -Wait      # stay attached (VS Code task)
   tools\superrstudio\dev-run.ps1 -DebugPort 19381         # DevTools/Playwright over CDP
   tools\superrstudio\dev-run.ps1 -RLibrary C:\empty-lib   # e.g. test without ggplot2
#>
[CmdletBinding()]
param(
   # Sets SUPER_RSTUDIO_EXPERIMENTAL=1 for the session (enables SuperRStudio features).
   [switch]$Experimental,
   # Isolated profile name under .cache\superrstudio\dev-profiles.
   [string]$ProfileName = 'default',
   # User R library for the session (default: the isolated test library holding ggplot2).
   [string]$RLibrary = '',
   # R used by the session.
   [string]$RExe = $(if ($env:RSTUDIO_WHICH_R) { $env:RSTUDIO_WHICH_R } else { 'C:\R\R-4.6.1\bin\x64\R.exe' }),
   # Chromium remote debugging port for DevTools / Playwright (0 = off).
   [int]$DebugPort = 0,
   # Node inspector port for the Electron main process (0 = off).
   [int]$InspectPort = 0,
   # Passes --automation-agent (enables the window.rstudio automation bridge).
   [switch]$Automation,
   # Wait for the desktop to exit and return its exit code.
   [switch]$Wait,
   # Native build to run (default build\superrstudio-windows), e.g. the pristine
   # baseline's build for comparisons; its session serves that build's client.
   [string]$BuildDir = ''
)

. (Join-Path $PSScriptRoot 'dev-common.ps1')

if (-not $BuildDir) { $BuildDir = $SrsBuildDir }
$session = Join-Path $BuildDir 'src\cpp\session\rsession.exe'
if (-not (Test-Path $session)) { throw "rsession.exe not built; run tools\superrstudio\dev-build.ps1 first." }
if (-not (Test-Path (Join-Path $SrsRoot 'src\gwt\www\rstudio\rstudio.nocache.js'))) { throw "GWT client not built; run tools\superrstudio\dev-build.ps1 -Component gwt." }
if (-not (Test-Path $RExe)) { throw "R not found: $RExe" }

$desktop = Get-SrsDesktopDir
$electron = Get-SrsElectronExe $desktop
$profileDir = Join-Path $SrsProfilesDir $ProfileName
if (-not $RLibrary) { $RLibrary = Join-Path $SrsCache 'r-library' }

$dirs = [ordered]@{
   RSTUDIO_CONFIG_HOME = 'config-home'; RSTUDIO_CONFIG_DIR = 'config-dir'
   RSTUDIO_DATA_HOME = 'data-home'; HOME = 'home'
}
foreach ($dir in @($dirs.Values) + 'electron-userdata' + 'work') { New-Item -ItemType Directory -Force (Join-Path $profileDir $dir) | Out-Null }
New-Item -ItemType Directory -Force $RLibrary | Out-Null

# Seed preferences once; later changes made in the IDE are kept.
$prefs = Join-Path $profileDir 'config-home\rstudio-prefs.json'
if (-not (Test-Path $prefs))
{
   @{ restore_last_project = $false; save_workspace = 'never'; load_workspace = $false
      check_for_updates = $false; initial_working_directory = ((Join-Path $profileDir 'work') -replace '\\', '/') } |
      ConvertTo-Json | Set-Content -Path $prefs -Encoding utf8
}

# Child environment: the launched process inherits these; they are restored in
# this shell afterwards so running the script never alters the caller.
$childEnv = [ordered]@{
   RSTUDIO_CPP_BUILD_OUTPUT = $BuildDir; RSTUDIO_WHICH_R = $RExe; R_LIBS_USER = $RLibrary
   R_PROFILE_USER = 'NUL'; R_ENVIRON_USER = 'NUL'; RSTUDIO_DISABLE_WHATS_NEW = '1'; RS_NO_SPLASH = '1'
   ELECTRON_RUN_AS_NODE = $null   # set by some hosts (e.g. VS Code); breaks Electron
   SUPER_RSTUDIO_EXPERIMENTAL = $(if ($Experimental) { '1' } else { $null })
}
foreach ($key in $dirs.Keys) { $childEnv[$key] = Join-Path $profileDir $dirs[$key] }
foreach ($key in 'LANG', 'LC_ALL', 'LC_CTYPE')
{
   if ([Environment]::GetEnvironmentVariable($key) -eq 'C.UTF-8') { $childEnv[$key] = $null }
}

# Electron loads ".\index.js" from the webpack main directory. RStudio's
# argument filter ignores "." (as in upstream's dev start), whereas a script
# path would be opened as a source document and used as the working directory.
$mainDir = Join-Path $desktop '.webpack\x64\main'
$arguments = @('.', "`"--user-data-dir=$profileDir\electron-userdata`"")
if ($DebugPort -gt 0) { $arguments += "--remote-debugging-port=$DebugPort" }
if ($InspectPort -gt 0) { $arguments = @("--inspect=$InspectPort") + $arguments }
if ($Automation) { $arguments += '--automation-agent' }

$stdoutLog = Join-Path $profileDir 'desktop.out.log'
$stderrLog = Join-Path $profileDir 'desktop.err.log'
$saved = @{}
foreach ($key in $childEnv.Keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key) }
try
{
   foreach ($key in $childEnv.Keys) { [Environment]::SetEnvironmentVariable($key, $childEnv[$key]) }
   $process = Start-Process -FilePath $electron -ArgumentList $arguments -WorkingDirectory $mainDir `
      -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
}
finally
{
   foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
}

Write-SrsStep "Desktop PID $($process.Id); experimental=$([bool]$Experimental); profile=$profileDir"
Write-SrsStep "Session: $session"
Write-SrsStep "R: $RExe; user library: $RLibrary"
Write-SrsStep "Electron output: $stdoutLog / $stderrLog; RStudio logs: $profileDir\data-home\log"
Set-Content -Path (Join-Path $profileDir 'pid.json') -Value (@{ pid = $process.Id; debugPort = $DebugPort } | ConvertTo-Json) -Encoding utf8

if ($Wait)
{
   $process.WaitForExit()
   Write-SrsStep "Desktop exited with code $($process.ExitCode)"
   exit $process.ExitCode
}
