<#
.SYNOPSIS
   Reproducible SuperRStudio benchmarks (R level and desktop).
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   R level: tools\superrstudio\bench\bench-r.R in the isolated library (dataset
   enumeration, inspect, code, preview rendering, TropFishR workflow).
   Desktop: for each configuration, launches the development desktop in its
   own isolated profile, runs tests\superrstudio\bench-desktop.cjs (start to
   ready, console round trips, plot-editor preview latency) and records the
   working set of the R session and of all Electron processes started by the
   launch, then quits through RStudio's quitSession command.

     baseline  the pristine upstream build (SUPER_RSTUDIO_BASELINE worktree)
     off       this fork's build with SuperRStudio features disabled
     on-idle   this fork's build with SUPER_RSTUDIO_EXPERIMENTAL=1, IDE idle (memory comparable)
     on        the same, then the plot editor previews 100,000-row data (latency)

   Results (JSON) and the system description go to .cache\superrstudio\bench.
   Nothing is installed and no user profile or library is touched.

.EXAMPLE
   tools\superrstudio\bench.ps1 -Runs 3
   tools\superrstudio\bench.ps1 -Skip r -Configurations on
#>
[CmdletBinding()]
param(
   [int]$Runs = 3,
   [int]$Repetitions = 5,
   [string[]]$Configurations = @('baseline', 'off', 'on-idle', 'on'),
   [ValidateSet('', 'r', 'desktop')]
   [string]$Skip = '',
   [int]$Port = 19381,
   [string]$Node = 'D:\Git\rstudio-tools\dependencies\common\node\22.22.2\node.exe',
   [string]$RScript = 'C:\R\R-4.6.1\bin\x64\Rscript.exe'
)

. (Join-Path $PSScriptRoot 'dev-common.ps1')
$Configurations = @($Configurations | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$out = Join-Path $SrsCache 'bench'
New-Item -ItemType Directory -Force $out | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# the machine, recorded with every result
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem
$system = [ordered]@{
   date = (Get-Date -Format o); cpu = $cpu.Name.Trim(); cores = $cpu.NumberOfCores
   logical_processors = $cpu.NumberOfLogicalProcessors
   memory_gb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
   os = "$($os.Caption) $($os.Version)"; commit = (git -C $SrsRoot rev-parse --short HEAD)
   power_plan = ((powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1')
}
Write-SrsStep ("System: {0}; {1} cores / {2} threads; {3} GB; {4}" -f $system.cpu, $system.cores,
   $system.logical_processors, $system.memory_gb, $system.os)

if ($Skip -ne 'r')
{
   Write-SrsStep "R-level benchmark ($Repetitions repetitions)"
   $env:R_LIBS_USER = Join-Path $SrsCache 'r-library'
   & $RScript (Join-Path $PSScriptRoot 'bench\bench-r.R') $Repetitions (Join-Path $out "r-$stamp.json") | Out-Host
}

if ($Skip -ne 'desktop')
{
   $env:NODE_PATH = Join-Path $SrsCache 'ui-client\node_modules'
   $env:SUPER_RSTUDIO_CDP_PORT = "$Port"
   $electronDir = Split-Path (Get-SrsElectronExe (Get-SrsDesktopDir))
   $rows = @()
   foreach ($config in $Configurations)
   {
      $run = @{ ProfileName = "bench-$config"; DebugPort = $Port; Automation = $true }
      if ($config -like 'on*') { $run.Experimental = $true }
      if ($config -eq 'baseline') { $run.BuildDir = Join-Path $SrsBaseline 'build\baseline-windows' }
      # run 0 warms the profile (first launch creates it) and is not recorded
      for ($i = 0; $i -le $Runs; $i++)
      {
         # the previous desktop may still be closing: wait up to a minute for its port
         for ($wait = 0; $wait -lt 60 -and (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue); $wait++)
         { Start-Sleep -Seconds 1 }
         if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { throw "Port $Port in use" }
         $launched = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
         $since = Get-Date
         & (Join-Path $PSScriptRoot 'dev-run.ps1') @run | Out-Null
         $desktopPid = (Get-Content (Join-Path $SrsProfilesDir "bench-$config\pid.json") -Raw | ConvertFrom-Json).pid
         try
         {
            $mode = if ($config -eq 'on') { 'on' } else { 'off' }
            $line = & $Node (Join-Path $SrsRoot 'tests\superrstudio\bench-desktop.cjs') $launched $mode |
               Where-Object { $_ -like 'BENCH *' } | Select-Object -Last 1
            if (-not $line) { throw "no measurement for $config run $i" }
            $result = $line.Substring(6) | ConvertFrom-Json
            # processes started by this launch: the R session and Electron's
            $procs = Get-Process | Where-Object { $_.StartTime -ge $since }
            # the desktop renames the session process (development.<hash>.rsession-utf8)
            $session = ($procs | Where-Object { $_.ProcessName -match 'rsession' } | Measure-Object WorkingSet64 -Sum).Sum
            $electron = ($procs | Where-Object { $_.Path -and $_.Path.StartsWith($electronDir) } |
                         Measure-Object WorkingSet64 -Sum).Sum
            $result | Add-Member config $config
            $result | Add-Member run $i
            $result | Add-Member session_mb ([math]::Round($session / 1MB, 1))
            $result | Add-Member electron_mb ([math]::Round($electron / 1MB, 1))
            if ($i -gt 0) { $rows += $result }
            Write-SrsStep ("{0,-8} run {1}: ready {2} ms; console {3} ms (max {4}); session {5} MB; Electron {6} MB{7}" -f
               $config, $i, $result.ready_ms, $result.console_median_ms, $result.console_max_ms, $result.session_mb,
               $result.electron_mb, $(if ($result.preview_lines_100k_ms) {
                  "; preview lines {0} ms ({1}), points {2} ms ({3})" -f $result.preview_lines_100k_ms,
                  $result.preview_lines_format, $result.preview_points_100k_ms, $result.preview_points_format } else { '' }))
         }
         finally
         {
            & $Node (Join-Path $PSScriptRoot 'dev-quit.cjs') $Port | Out-Null
            Wait-Process -Id $desktopPid -Timeout 60 -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
         }
      }
   }
   [ordered]@{ system = $system; runs = $rows } | ConvertTo-Json -Depth 5 |
      Set-Content -Path (Join-Path $out "desktop-$stamp.json") -Encoding utf8
   Write-SrsStep "Medians:"
   foreach ($config in $Configurations)
   {
      $set = @($rows | Where-Object { $_.config -eq $config })
      $median = { param($values) $sorted = @($values | Sort-Object); $sorted[[int][math]::Floor($sorted.Count / 2)] }
      Write-SrsStep ("{0,-8} ready {1} ms; console {2} ms; session {3} MB; Electron {4} MB" -f $config,
         (& $median $set.ready_ms), (& $median $set.console_median_ms), (& $median $set.session_mb), (& $median $set.electron_mb))
   }
   Write-SrsStep "Written to $out\desktop-$stamp.json"
}
