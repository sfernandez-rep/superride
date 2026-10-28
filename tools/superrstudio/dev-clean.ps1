<#
.SYNOPSIS
   Safe cleanup of SuperRStudio development outputs. Nothing is removed unless asked.
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   Only removes outputs that dev-build.ps1 / dev-run.ps1 can recreate inside
   this checkout. It never touches the baseline worktree, the shared
   dependency tree (rstudio-tools), the isolated R library, the cached
   Electron runtime, sources, or any installed RStudio and its settings.
   Supports -WhatIf.

.EXAMPLE
   tools\superrstudio\dev-clean.ps1 -ProfileName gui-scatter     # one isolated profile
   tools\superrstudio\dev-clean.ps1 -AllProfiles
   tools\superrstudio\dev-clean.ps1 -Gwt                     # upstream `ant clean`
   tools\superrstudio\dev-clean.ps1 -Native                  # ninja clean (keeps configuration)
   tools\superrstudio\dev-clean.ps1 -Native -Gwt -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
   [string[]]$ProfileName = @(),
   [switch]$AllProfiles,
   [switch]$Gwt,
   [switch]$Native
)

. (Join-Path $PSScriptRoot 'dev-common.ps1')

if (-not ($ProfileName.Count -or $AllProfiles -or $Gwt -or $Native))
{
   Write-Host 'Nothing selected. Use -ProfileName NAME, -AllProfiles, -Gwt and/or -Native (add -WhatIf to preview).'
   exit 0
}

function Assert-NotRunning([string]$Dir)
{
   $pidFile = Join-Path $Dir 'pid.json'
   if (Test-Path $pidFile)
   {
      $info = Get-Content $pidFile -Raw | ConvertFrom-Json
      if (Get-Process -Id $info.pid -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq 'electron' })
      {
         throw "A development desktop (PID $($info.pid)) is still using $Dir; quit it first."
      }
   }
}

$targets = @()
if ($AllProfiles -and (Test-Path $SrsProfilesDir)) { $targets += @(Get-ChildItem $SrsProfilesDir -Directory).FullName }
# `powershell -File` passes "a,b" as one string, so split on commas too.
foreach ($name in @($ProfileName | ForEach-Object { $_ -split ',' } | Where-Object { $_ }))
{
   # a plain name only: no separators, and never '.'/'..' (would escape dev-profiles)
   if ($name -notmatch '^[A-Za-z0-9_][\w.-]*$') { throw "Invalid profile name: $name" }
   $targets += Join-Path $SrsProfilesDir $name
}
foreach ($dir in $targets | Select-Object -Unique)
{
   if (-not (Test-Path $dir)) { Write-SrsStep "No profile at $dir"; continue }
   Assert-NotRunning $dir
   if ($PSCmdlet.ShouldProcess($dir, 'Remove isolated development profile'))
   {
      Remove-Item -LiteralPath $dir -Recurse -Force
      Write-SrsStep "Removed $dir"
   }
}

if ($Gwt -and $PSCmdlet.ShouldProcess("$SrsRoot\src\gwt", 'ant clean (GWT outputs; panmirror is restored on the next build)'))
{
   $code = Invoke-SrsBuildEnv "cd /d `"$SrsRoot\src\gwt`" && ant -f `"$SrsGwtXml`" clean"
   if ($code -ne 0) { throw "ant clean failed (exit $code)." }
   Remove-Item -LiteralPath (Join-Path $SrsStampDir 'gwt-draft.stamp') -ErrorAction SilentlyContinue
   Write-SrsStep 'GWT outputs cleaned'
}

if ($Native -and (Test-Path (Join-Path $SrsBuildDir 'build.ninja')) -and
    $PSCmdlet.ShouldProcess($SrsBuildDir, 'ninja clean (configuration and fetched dependencies kept)'))
{
   $code = Invoke-SrsBuildEnv "cmake --build `"$SrsBuildDir`" --target clean"
   if ($code -ne 0) { throw "Native clean failed (exit $code)." }
   Write-SrsStep 'Native outputs cleaned; the next native build is a full (~20 min) compile'
}
