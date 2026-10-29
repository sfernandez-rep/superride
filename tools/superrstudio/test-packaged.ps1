<#
.SYNOPSIS
   Installs the SuperR installer for the current user, tests the installed
   application, uninstalls it and checks that nothing else changed.
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   Steps (results and screenshots in .cache\superrstudio\packaged-tests\<time>):

     1. snapshot: RStudio's settings folders (%APPDATA%\RStudio,
        %LOCALAPPDATA%\RStudio), default programs of R file types, RStudio.*
        ProgIDs, R libraries, and the synthetic project fixture
     2. silent per-user install (/S /currentuser); checks the folder,
        executable metadata and icon, Start Menu shortcut, Apps & features
        entry, App Paths and SuperR.* ProgIDs; file types not taken over
     3. a copy of tests\superrstudio\fixtures\rstudio-project is opened in the
        installed SuperR.exe four times (tests\superrstudio\packaged-app.cjs):
        nopkg (empty user library: the optional-package prompt, Cancel) /
        first / restart / off (SUPER_RSTUDIO_EXPERIMENTAL=0)
     4. silent uninstall; checks that SuperR's files, shortcut and registry
        entries are gone and that every snapshot from step 1 is unchanged

   SuperR runs with the user's registered R. -RLibrary is added to the R
   library path of the launched application only (R_LIBS_USER for that
   process), so ggplot2 and TropFishR are available without installing
   anything into the user's libraries. If %APPDATA%\SuperR or
   %LOCALAPPDATA%\SuperR exist from an earlier run they are moved into the
   evidence folder first, so the first launch is a fresh one.

   Requires the Playwright client in .cache\superrstudio\ui-client.

.EXAMPLE
   tools\superrstudio\test-packaged.ps1
   tools\superrstudio\test-packaged.ps1 -KeepInstalled
#>
[CmdletBinding()]
param(
   [string]$Installer,
   [string]$RLibrary,
   [int]$Port = 19391,
   [switch]$KeepInstalled,
   [string]$Node = 'D:\Git\rstudio-tools\dependencies\common\node\22.22.2\node.exe'
)

. (Join-Path $PSScriptRoot 'dev-common.ps1')
$product = Get-Content (Join-Path $SrsRoot 'package\superr\product.json') -Raw | ConvertFrom-Json
if (-not $Installer)
{
   $Installer = Get-ChildItem (Join-Path $SrsRoot 'dist\superr') -Filter "$($product.productName)-*-Windows-x64.exe" |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Installer -or -not (Test-Path $Installer)) { throw 'No installer found; run package-superr.ps1 first.' }
if (-not $RLibrary) { $RLibrary = Join-Path $SrsCache 'r-library' }
$env:NODE_PATH = Join-Path $SrsCache 'ui-client\node_modules'
$env:SUPER_RSTUDIO_CDP_PORT = "$Port"
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { throw "Port $Port is in use." }
if (Get-Process -Name $product.executableName -ErrorAction SilentlyContinue) { throw "$($product.executableName).exe is already running." }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$evidence = Join-Path $SrsCache "packaged-tests\$stamp"
New-Item -ItemType Directory -Force $evidence | Out-Null
$results = New-Object System.Collections.Generic.List[object]
function Record([string]$Name, [bool]$Ok, [string]$Detail = '')
{
   $results.Add([pscustomobject]@{ phase = 'host'; name = $Name; result = $(if ($Ok) { 'PASS' } else { 'FAIL' }); detail = $Detail })
   $color = if ($Ok) { 'Green' } else { 'Red' }
   Write-Host ("{0} {1} {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail) -ForegroundColor $color
}

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class SuperRWindow
{
   [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
   [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
}
"@
function Test-Port([int]$Number)
{
   $client = New-Object System.Net.Sockets.TcpClient
   try { $client.Connect('127.0.0.1', $Number); return $true } catch { return $false } finally { $client.Dispose() }
}
# the main window of the installed SuperR.exe (title and a capture of the window only)
function Get-AppWindow
{
   Get-Process -Name $product.executableName -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle } | Select-Object -First 1
}

$exts = '.R', '.Rproj', '.Rmd', '.qmd', '.RData', '.rda', '.Rd', '.md', '.html'
function Get-Snapshot
{
   $files = foreach ($dir in "$env:APPDATA\RStudio", "$env:LOCALAPPDATA\RStudio")
   {
      if (Test-Path $dir)
      {
         Get-ChildItem $dir -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { "{0}|{1}|{2:o}" -f $_.FullName, $_.Length, $_.LastWriteTimeUtc }
      }
   }
   $defaults = foreach ($ext in $exts)
   {
      foreach ($hive in 'HKCU:', 'HKLM:')
      {
         $key = "$hive\Software\Classes\$ext"
         # a missing key and an empty default both mean "no default program"
         $value = if (Test-Path $key) { (Get-Item $key).GetValue('') } else { '' }
         "$key=$value"
      }
      $choice = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
      "$choice=$(if (Test-Path $choice) { (Get-ItemProperty $choice).ProgId } else { '<none>' })"
   }
   $progids = foreach ($hive in 'HKCU:', 'HKLM:')
   {
      Get-ChildItem "$hive\Software\Classes" -ErrorAction SilentlyContinue |
         Where-Object { $_.PSChildName -like 'RStudio.*' } | ForEach-Object { $_.Name }
   }
   $libraries = foreach ($lib in 'C:\R\R-4.6.1\library', "$env:LOCALAPPDATA\R\win-library", $RLibrary)
   {
      if (Test-Path $lib)
      {
         Get-ChildItem $lib -Recurse -Filter DESCRIPTION -Depth 2 -ErrorAction SilentlyContinue |
            ForEach-Object { "{0}|{1:o}" -f $_.FullName, $_.LastWriteTimeUtc }
      }
   }
   $fixture = Get-ChildItem (Join-Path $SrsRoot 'tests\superrstudio\fixtures\rstudio-project') -Recurse -File |
      ForEach-Object { "{0}|{1}" -f $_.FullName, (Get-FileHash $_.FullName).Hash }
   [pscustomobject]@{ rstudioFiles = @($files); defaults = @($defaults); rstudioProgIds = @($progids)
                      libraries = @($libraries); fixture = @($fixture) }
}
function Compare-Snapshot($Before, $After, [string]$When)
{
   foreach ($part in 'rstudioFiles', 'defaults', 'rstudioProgIds', 'libraries', 'fixture')
   {
      $diff = Compare-Object @($Before.$part) @($After.$part)
      $detail = if ($diff) { ($diff | Select-Object -First 5 | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; ' }
                else { "$(@($Before.$part).Count) entries" }
      Record "$When`: $part unchanged" (-not $diff) $detail
   }
}

# 1. snapshot; move away SuperR user data from an earlier run
$before = Get-Snapshot
$before | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $evidence 'snapshot-before.json') -Encoding utf8
foreach ($dir in "$env:APPDATA\$($product.userFolder)", "$env:LOCALAPPDATA\$($product.userFolder)")
{
   if (Test-Path $dir) { Move-Item $dir (Join-Path $evidence ("previous-" + ($dir -replace '[:\\]', '_'))) }
}

# 2. install for the current user
$installDir = Join-Path $env:LOCALAPPDATA "Programs\$($product.installDirectory)"
$exe = Join-Path $installDir "$($product.executableName).exe"
$started = Get-Date
$proc = Start-Process $Installer -ArgumentList '/S', '/currentuser' -Wait -PassThru
Record 'silent per-user install exits 0' ($proc.ExitCode -eq 0) ("exit {0}, {1:n0} s" -f $proc.ExitCode, ((Get-Date) - $started).TotalSeconds)
Record 'installed to its own folder' (Test-Path $exe) $exe
if (-not (Test-Path $exe)) { throw 'Installation failed; see above.' }
$info = (Get-Item $exe).VersionInfo
Record 'executable metadata is SuperR' ($info.ProductName -eq $product.productName -and $info.CompanyName -eq $product.vendor) `
   "$($info.ProductName) / $($info.CompanyName) / $($info.FileDescription)"
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
$iconPng = Join-Path $evidence 'exe-icon-32.png'
$icon.ToBitmap().Save($iconPng)
$ref = [System.Drawing.Bitmap]::FromFile((Join-Path $SrsRoot 'assets\branding\generated\png\superr-32.png'))
$got = [System.Drawing.Bitmap]::FromFile($iconPng)
$sum = 0
for ($y = 0; $y -lt 32; $y++) { for ($x = 0; $x -lt 32; $x++) {
   $a = $ref.GetPixel($x, $y); $b = $got.GetPixel($x, $y)
   $sum += [Math]::Abs($a.A - $b.A) + [Math]::Abs($a.R - $b.R) + [Math]::Abs($a.G - $b.G) + [Math]::Abs($a.B - $b.B) } }
$ref.Dispose(); $got.Dispose()
$meanDiff = $sum / (32 * 32 * 4)
Record 'executable icon is the SuperR icon' ($meanDiff -lt 8) ("mean channel difference {0:n2} against superr-32.png" -f $meanDiff)
$lnk = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$($product.productName).lnk"
$target = if (Test-Path $lnk) { (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath } else { '' }
Record 'Start Menu shortcut points to SuperR.exe' ($target -eq $exe) "$lnk -> $target"
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($product.productName)"
$entry = if (Test-Path $uninstallKey) { Get-ItemProperty $uninstallKey } else { $null }
Record 'Apps & features entry' ($entry -and $entry.DisplayName -like "$($product.productName)*") `
   $(if ($entry) { "$($entry.DisplayName) | $($entry.DisplayVersion) | $($entry.Publisher) | $($entry.InstallLocation)" })
Record 'App Paths entry for SuperR.exe' (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\$($product.executableName).exe")
$superrIds = @(Get-ChildItem 'HKCU:\Software\Classes' | Where-Object { $_.PSChildName -like "$($product.progIdPrefix).*" } | ForEach-Object PSChildName)
Record 'SuperR file-type ProgIDs registered (offered in Open with)' ($superrIds.Count -eq 16) ($superrIds -join ', ')
$offered = (Get-ItemProperty 'HKCU:\Software\Classes\.Rproj\OpenWithProgids' -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains "$($product.progIdPrefix).Rproj"
Record '.Rproj offers SuperR in Open with' $offered
$afterInstall = Get-Snapshot
Compare-Snapshot $before $afterInstall 'after install'

# 3. the installed application, three launches on a copy of the fixture
$work = Join-Path $evidence 'project-copy\rstudio-project'
New-Item -ItemType Directory -Force (Split-Path $work) | Out-Null
Copy-Item -Recurse (Join-Path $SrsRoot 'tests\superrstudio\fixtures\rstudio-project') $work
# nopkg: the first start, with an empty user library (no ggplot2 or
# TropFishR anywhere): SuperR starts, asks before installing, works on
$emptyLibrary = Join-Path $evidence 'empty-library'
New-Item -ItemType Directory -Force $emptyLibrary | Out-Null
$phases = @(
   @{ name = 'nopkg'; args = @((Join-Path $work 'survey.Rproj')); experimental = $null; library = $emptyLibrary },
   @{ name = 'first'; args = @(); experimental = $null },
   @{ name = 'restart'; args = @(); experimental = $null },
   @{ name = 'off'; args = @(); experimental = '0' })
foreach ($phase in $phases)
{
   $env:R_LIBS_USER = if ($phase.library) { $phase.library } else { $RLibrary }
   if ($phase.experimental) { $env:SUPER_RSTUDIO_EXPERIMENTAL = $phase.experimental } else { Remove-Item Env:SUPER_RSTUDIO_EXPERIMENTAL -ErrorAction SilentlyContinue }
   $launch = Get-Date
   $app = Start-Process $exe -ArgumentList (@("--remote-debugging-port=$Port", '--automation-agent') + $phase.args) -PassThru
   Remove-Item Env:R_LIBS_USER, Env:SUPER_RSTUDIO_EXPERIMENTAL -ErrorAction SilentlyContinue
   $ready = $false
   while (-not $ready -and ((Get-Date) - $launch).TotalSeconds -lt 180)
   {
      Start-Sleep -Milliseconds 250
      $ready = Test-Port $Port
   }
   Record "$($phase.name): SuperR.exe started (debugging port open)" $ready ("{0:n1} s" -f ((Get-Date) - $launch).TotalSeconds)
   & $Node (Join-Path $SrsRoot 'tests\superrstudio\packaged-app.cjs') $phase.name $work $evidence | Out-Host
   $phaseOk = ($LASTEXITCODE -eq 0)
   # the window title and a capture of the SuperR window only (title bar and
   # icon); never the whole screen, which would record unrelated applications
   $window = Get-AppWindow
   Record "$($phase.name): window title carries the SuperR name" ($window -and $window.MainWindowTitle -match 'SuperR' -and
      $window.MainWindowTitle -notmatch 'RStudio') $(if ($window) { $window.MainWindowTitle })
   if ($window)
   {
      $rect = New-Object SuperRWindow+RECT
      [void][SuperRWindow]::GetWindowRect($window.MainWindowHandle, [ref]$rect)
      $w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
      if ($w -gt 0 -and $h -gt 0)
      {
         $capture = New-Object System.Drawing.Bitmap $w, $h
         $g = [System.Drawing.Graphics]::FromImage($capture)
         $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
         $capture.Save((Join-Path $evidence "window-$($phase.name).png"))
         $g.Dispose(); $capture.Dispose()
      }
   }
   $phaseFile = Join-Path $evidence "packaged-$($phase.name).json"
   if (Test-Path $phaseFile) { (Get-Content $phaseFile -Raw | ConvertFrom-Json) | ForEach-Object { $results.Add($_) } }
   # quit the way a user would: q() in the console ends the session and closes the window
   & $Node (Join-Path $PSScriptRoot 'dev-quit.cjs') $Port | Out-Host
   if (-not $app.WaitForExit(90000))
   {
      Record "$($phase.name): SuperR closed by quitSession" $false 'still running after 90 s; stopped'
      Stop-Process -Id $app.Id -Force
      Get-Process rsession* -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$installDir*" } | Stop-Process -Force
   }
   else { Record "$($phase.name): SuperR closed by quitSession" $true }
   Start-Sleep -Seconds 3
   if (-not $phaseOk) { Write-Warning "Phase $($phase.name) failed; continuing to uninstall." }
}
$userConfig = Join-Path $env:APPDATA $product.userFolder
Record 'SuperR settings written to its own folder' (Test-Path (Join-Path $userConfig 'rstudio-prefs.json')) $userConfig

# 4. uninstall
if (-not $KeepInstalled)
{
   $un = Start-Process (Join-Path $installDir 'Uninstall.exe') -ArgumentList '/S', '/currentuser' -Wait -PassThru
   for ($i = 0; $i -lt 120 -and ((Test-Path $exe) -or (Test-Path $uninstallKey)); $i++) { Start-Sleep -Seconds 1 }
   Record 'silent uninstall' (-not (Test-Path $exe)) "exit $($un.ExitCode)"
   Record 'install folder removed' (-not (Test-Path $installDir)) $installDir
   Record 'Start Menu shortcut removed' (-not (Test-Path $lnk))
   Record 'Apps & features entry removed' (-not (Test-Path $uninstallKey))
   Record 'App Paths entry removed' (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\$($product.executableName).exe"))
   $left = @(Get-ChildItem 'HKCU:\Software\Classes' | Where-Object { $_.PSChildName -like "$($product.progIdPrefix).*" })
   Record 'SuperR ProgIDs removed' ($left.Count -eq 0) ($left.PSChildName -join ', ')
   $stillOffered = (Get-ItemProperty 'HKCU:\Software\Classes\.Rproj\OpenWithProgids' -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains "$($product.progIdPrefix).Rproj"
   Record '.Rproj Open with entry removed' (-not $stillOffered)
   Record 'nothing installed into the empty library (prompt cancelled)' (-not (Get-ChildItem $emptyLibrary -Force)) $emptyLibrary
   Record 'project copy and its outputs kept' (Test-Path (Join-Path $work 'output\summary.csv')) $work
   Record 'user settings kept (not removed by the uninstaller)' (Test-Path $userConfig) $userConfig
   $after = Get-Snapshot
   $after | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $evidence 'snapshot-after.json') -Encoding utf8
   Compare-Snapshot $before $after 'after uninstall'
}

$results | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $evidence 'results.json') -Encoding utf8
$failed = @($results | Where-Object result -ne 'PASS')
Write-Host ("{0} checks, {1} failed. Evidence: {2}" -f $results.Count, $failed.Count, $evidence)
if ($failed.Count) { exit 1 }
