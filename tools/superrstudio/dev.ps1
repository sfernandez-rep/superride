<#
.SYNOPSIS
   Incremental build, then launch the SuperRStudio development desktop.
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   Runs dev-build.ps1 (native + GWT, incremental) and, if it succeeds,
   dev-run.ps1. Parameters are forwarded to dev-run.ps1.

.EXAMPLE
   tools\superrstudio\dev.ps1 -Experimental
   tools\superrstudio\dev.ps1 -Experimental -Wait -DebugPort 19381
#>
[CmdletBinding()]
param(
   [switch]$Experimental,
   [string]$ProfileName = 'default',
   [string]$RLibrary = '',
   [string]$RExe = '',
   [int]$DebugPort = 0,
   [int]$InspectPort = 0,
   [switch]$Automation,
   [switch]$Wait,
   # Skip the build step (same as running dev-run.ps1 directly).
   [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
if (-not $NoBuild) { & (Join-Path $PSScriptRoot 'dev-build.ps1') }

$run = @{ ProfileName = $ProfileName; DebugPort = $DebugPort; InspectPort = $InspectPort }
if ($Experimental) { $run.Experimental = $true }
if ($Automation) { $run.Automation = $true }
if ($Wait) { $run.Wait = $true }
if ($RLibrary) { $run.RLibrary = $RLibrary }
if ($RExe) { $run.RExe = $RExe }
& (Join-Path $PSScriptRoot 'dev-run.ps1') @run
