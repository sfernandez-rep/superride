<#
.SYNOPSIS
   Opens a COPY of an existing RStudio project in the installed SuperR and
   reports what changed. The original project is never opened or modified.
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   1. Hashes every file of the original project folder.
   2. Copies the folder to a new folder (default under %TEMP%\SuperR-project-tests).
   3. Starts the installed SuperR on the copy's .Rproj (or on the folder when
      there is none) and waits until you close SuperR. Work normally: open
      scripts, run code, make plots. Running scripts may create or change
      files - in the copy only.
   4. Re-hashes the original (it must be unchanged) and lists the files that
      were added, changed or removed in the copy, so you can see what your
      scripts wrote.

   SuperR does not convert projects: .Rproj, .R, .Rmd, .qmd, .RData, .rds,
   CSV, renv and package files are used as they are. Nothing is uploaded.

.EXAMPLE
   tools\superrstudio\test-project-copy.ps1 -Project "D:\research\otolith-growth"
   tools\superrstudio\test-project-copy.ps1 -Project "D:\research\otolith-growth" -Destination "E:\tmp"
#>
[CmdletBinding()]
param(
   [Parameter(Mandatory)] [string]$Project,
   [string]$Destination = (Join-Path $env:TEMP 'SuperR-project-tests'),
   [string]$SuperR = (Join-Path $env:LOCALAPPDATA 'Programs\SuperR\SuperR.exe')
)
$ErrorActionPreference = 'Stop'
$Project = (Resolve-Path $Project).Path
if (-not (Test-Path $Project -PathType Container)) { throw "Not a folder: $Project" }
if (-not (Test-Path $SuperR)) { $SuperR = Join-Path $env:ProgramFiles 'SuperR\SuperR.exe' }
if (-not (Test-Path $SuperR)) { throw 'SuperR is not installed (SuperR.exe not found); pass -SuperR <path>.' }

function Get-Hashes([string]$Root)
{
   $table = @{}
   Get-ChildItem $Root -Recurse -File -Force | ForEach-Object {
      $table[$_.FullName.Substring($Root.Length).TrimStart('\')] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
   }
   return $table
}

Write-Host "Hashing the original project: $Project"
$original = Get-Hashes $Project
$copy = Join-Path $Destination ("{0}-{1}" -f (Split-Path $Project -Leaf), (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $copy | Out-Null
Write-Host "Copying $($original.Count) files to $copy"
# -Force includes hidden files (.Rprofile, .Rproj.user, renv's files)
Copy-Item -Path (Join-Path $Project '*') -Destination $copy -Recurse -Force
$copied = Get-Hashes $copy

$rproj = Get-ChildItem $copy -Filter *.Rproj | Select-Object -First 1
$target = if ($rproj) { $rproj.FullName } else { $copy }
Write-Host "Starting SuperR on $target"
Write-Host 'Work with the project, then close SuperR to see the report.' -ForegroundColor Cyan
Start-Process $SuperR -ArgumentList "`"$target`"" -Wait

$after = Get-Hashes $Project
$changedOriginal = @($original.Keys | Where-Object { $after[$_] -ne $original[$_] }) + @($after.Keys | Where-Object { -not $original.ContainsKey($_) })
if ($changedOriginal.Count)
{
   Write-Host "WARNING: the original project changed while the copy was open (another program?):" -ForegroundColor Red
   $changedOriginal | ForEach-Object { Write-Host "  $_" }
}
else { Write-Host "Original project unchanged ($($original.Count) files verified by SHA-256)." -ForegroundColor Green }

$final = Get-Hashes $copy
$added = @($final.Keys | Where-Object { -not $copied.ContainsKey($_) } | Sort-Object)
$changed = @($final.Keys | Where-Object { $copied.ContainsKey($_) -and $copied[$_] -ne $final[$_] } | Sort-Object)
$removed = @($copied.Keys | Where-Object { -not $final.ContainsKey($_) } | Sort-Object)
Write-Host "In the copy: $($added.Count) added, $($changed.Count) changed, $($removed.Count) removed"
foreach ($group in @(@('added', $added), @('changed', $changed), @('removed', $removed)))
{
   foreach ($file in $group[1]) { Write-Host ("  {0,-8} {1}" -f $group[0], $file) }
}
Write-Host "The copy stays at $copy for inspection; delete it when done."
