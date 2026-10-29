<#
.SYNOPSIS
   Live desktop acceptance for the visual scatter workflow (three scenarios).
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   For each scenario: launches the development desktop with dev-run.ps1 in an
   isolated profile, waits for the Chromium debugging port, runs
   tests/superrstudio/desktop-scatter.cjs and quits through RStudio's own
   quitSession command. Requires a prior dev-build.ps1 and the Playwright client
   in .cache\superrstudio\ui-client (see windows-gui-2026-10-28.md).

     ggplot2     -Experimental, isolated library with ggplot2
     no-ggplot2  -Experimental, empty library (missing-package path)
     disabled    no -Experimental (button hidden, IDE unchanged)
     lfq         -Experimental, isolated library with TropFishR (length-frequency
                 workflow; tests\superrstudio\desktop-lfq.cjs; not in the default set)
     es          -Experimental with ui_language "es": SuperRStudio windows in Spanish
                 (tests\superrstudio\desktop-es.cjs; not in the default set)
     visual      the Visual workbench tab and pane-layout migration: one profile
                 launched three times (a layout saved before the tab existed,
                 experimental; restart; features off) with desktop-visual.cjs

   Screenshots and generated code go to .cache\superrstudio\gui-scatter.
#>
[CmdletBinding()]
param(
   # ggplot2, no-ggplot2 and/or disabled (comma-separated works with -File too)
   [string[]]$Scenario = @('ggplot2', 'no-ggplot2', 'disabled'),
   [int]$Port = 19381,
   [string]$Node = 'D:\Git\rstudio-tools\dependencies\common\node\22.22.2\node.exe'
)

. (Join-Path $PSScriptRoot 'dev-common.ps1')
$Scenario = @($Scenario | ForEach-Object { $_ -split ',' } | Where-Object { $_ } |
   ForEach-Object { if ($_ -eq 'visual') { 'visual-migrate', 'visual-restart', 'visual-off' } else { $_ } })
foreach ($name in $Scenario)
{
   if ($name -notin 'ggplot2', 'no-ggplot2', 'disabled', 'lfq', 'es', 'visual-migrate', 'visual-restart', 'visual-off')
   { throw "Unknown scenario: $name" }
}
$env:NODE_PATH = Join-Path $SrsCache 'ui-client\node_modules'
$env:SUPER_RSTUDIO_CDP_PORT = "$Port"
if (-not (Test-Path (Join-Path $env:NODE_PATH 'playwright'))) { throw "Playwright client missing under $env:NODE_PATH" }
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { throw "Port $Port is already in use (another desktop running?)" }

$results = [ordered]@{}
foreach ($name in $Scenario)
{
   $profileName = if ($name -like 'visual-*') { 'gui-visual' } else { "gui-$name" }
   $run = @{ ProfileName = $profileName; DebugPort = $Port; Automation = $true }
   if ($name -notin 'disabled', 'visual-off') { $run.Experimental = $true }
   if ($name -eq 'visual-migrate')
   {
      # a customised layout saved by RStudio before the Visual tab existed
      # (History and Help swapped; no hiddenTabSet or sidebar fields)
      $configHome = Join-Path $SrsProfilesDir "$profileName\config-home"
      New-Item -ItemType Directory -Force $configHome | Out-Null
      $work = (Join-Path $SrsProfilesDir "$profileName\work") -replace '\\', '/'
      @{ restore_last_project = $false; save_workspace = 'never'; load_workspace = $false
         check_for_updates = $false; initial_working_directory = $work
         panes = @{ quadrants = @('Source', 'Console', 'TabSet1', 'TabSet2', 'HiddenTabSet', 'Sidebar')
                    tabSet1 = @('Environment', 'Help', 'Connections', 'Build', 'VCS', 'Tutorial', 'Presentation')
                    tabSet2 = @('Files', 'Plots', 'Packages', 'History', 'Viewer', 'Presentations')
                    console_left_on_top = $false; console_right_on_top = $true; additional_source_columns = 0 } } |
         ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $configHome 'rstudio-prefs.json') -Encoding utf8
   }
   if ($name -eq 'no-ggplot2') { $run.RLibrary = Join-Path $SrsProfilesDir "$profileName\empty-library" }
   if ($name -eq 'es')
   {
      # the user-interface language preference, seeded like dev-run.ps1 does
      $configHome = Join-Path $SrsProfilesDir "$profileName\config-home"
      New-Item -ItemType Directory -Force $configHome | Out-Null
      $work = (Join-Path $SrsProfilesDir "$profileName\work") -replace '\\', '/'
      @{ restore_last_project = $false; save_workspace = 'never'; load_workspace = $false
         check_for_updates = $false; initial_working_directory = $work; ui_language = 'es' } |
         ConvertTo-Json | Set-Content -Path (Join-Path $configHome 'rstudio-prefs.json') -Encoding utf8
   }

   Write-SrsStep "Scenario $name"
   & (Join-Path $PSScriptRoot 'dev-run.ps1') @run
   $desktopPid = (Get-Content (Join-Path $SrsProfilesDir "$profileName\pid.json") -Raw | ConvertFrom-Json).pid
   try
   {
      $up = $false
      for ($i = 0; $i -lt 90 -and -not $up; $i++)
      {
         try { Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port/json/version" -TimeoutSec 2 | Out-Null; $up = $true }
         catch { Start-Sleep -Seconds 2 }
      }
      if (-not $up) { throw "Desktop did not open debugging port $Port" }
      $test = switch -Wildcard ($name) { 'lfq' { 'desktop-lfq.cjs' } 'es' { 'desktop-es.cjs' } 'visual-*' { 'desktop-visual.cjs' }
                                         default { 'desktop-scatter.cjs' } }
      $argument = if ($name -like 'visual-*') { $name.Substring(7) } else { $name }
      & $Node (Join-Path $SrsRoot "tests\superrstudio\$test") $argument | Out-Host
      $results[$name] = if ($LASTEXITCODE -eq 0) { 'PASS' } else { "FAIL (exit $LASTEXITCODE)" }
   }
   catch { $results[$name] = "FAIL ($($_.Exception.Message))" }
   finally
   {
      & $Node (Join-Path $PSScriptRoot 'dev-quit.cjs') $Port | Out-Host
      Wait-Process -Id $desktopPid -Timeout 60 -ErrorAction SilentlyContinue
      if (Get-Process -Id $desktopPid -ErrorAction SilentlyContinue) { $results[$name] += ' (desktop did not quit)' }
   }
}

$results.GetEnumerator() | ForEach-Object { Write-SrsStep ("{0,-11} {1}" -f $_.Key, $_.Value) }
if ($results.Values | Where-Object { $_ -ne 'PASS' }) { exit 1 }
