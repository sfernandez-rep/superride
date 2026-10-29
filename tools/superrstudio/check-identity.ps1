<#
.SYNOPSIS
   Checks that every copy of the SuperR product identity matches
   package/superr/product.json, and that the generated branding is current.
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   CMake (package/, src/node/desktop) and the Electron packager read
   product.json directly. The GWT client, the desktop runtime and the R
   session cannot, so they hold small copies; this script fails when a copy
   drifts. It also checks that assets/branding/generated was produced from
   the current logo master and that the About-dialog logo is the generated
   one. Exit code 0 when everything matches.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$product = Get-Content (Join-Path $root 'package\superr\product.json') -Raw | ConvertFrom-Json
$failures = New-Object System.Collections.Generic.List[string]

function Read-Text([string]$Relative) { [IO.File]::ReadAllText((Join-Path $root $Relative)) }

function Expect([string]$Where, [string]$Pattern, [string]$Expected)
{
   $text = Read-Text $Where
   $m = [regex]::Match($text, $Pattern)
   if (-not $m.Success) { $failures.Add("$Where`: pattern not found ($Pattern)"); return }
   if ($m.Groups[1].Value -ne $Expected)
   {
      $failures.Add("$Where`: '$($m.Groups[1].Value)' but product.json has '$Expected'")
   }
}

$java = 'src\gwt\src\org\rstudio\studio\client\workbench\views\superrstudio\SuperRProduct.java'
Expect $java 'NAME = "([^"]*)"' $product.productName
Expect $java 'VERSION = "([^"]*)"' $product.version
Expect $java 'PRERELEASE = "([^"]*)"' $product.prerelease
Expect $java 'HOMEPAGE = "([^"]*)"' $product.homepage
$notice = [regex]::Match((Read-Text $java), 'NOTICE =\s*((?:"[^"]*"\s*\+?\s*)+);').Groups[1].Value
$notice = ([regex]::Matches($notice, '"([^"]*)"') | ForEach-Object { $_.Groups[1].Value }) -join ''
if ($notice -ne $product.notice) { $failures.Add("$java`: NOTICE differs from product.json") }

$ts = 'src\node\desktop\src\main\superr-identity.ts'
Expect $ts "kSuperRProductName = '([^']*)'" $product.productName
Expect $ts "kSuperRUserFolder = '([^']*)'" $product.userFolder

foreach ($lang in 'en', 'fr')
{
   Expect "src\gwt\src\org\rstudio\studio\client\application\StudioClientApplicationConstants_$lang.properties" `
      'rStudioEditionName=([^{\r\n]*)\{0\}' $product.productName
}
Expect 'src\cpp\session\modules\SessionSuperRStudio.R' "superrstudioBrand', function\(\) '([^']*)'" $product.productName

# generated branding: produced from the current master, logo copy current
$manifest = Read-Text 'assets\branding\generated\manifest.txt'
$masterHash = (Get-FileHash (Join-Path $root 'assets\branding\source\logo-master.png') -Algorithm SHA256).Hash
if ($manifest -notmatch "source sha256: $masterHash")
{
   $failures.Add('assets/branding/generated is not from the current logo master; run tools/superrstudio/branding/make-branding.ps1')
}
foreach ($line in ($manifest -split "`r?`n") | Where-Object { $_ -match '^[0-9a-f]{64}  ' })
{
   $hash, $rel = $line -split '  ', 2
   $file = Join-Path $root "assets\branding\generated\$rel"
   if (-not (Test-Path $file) -or (Get-FileHash $file -Algorithm SHA256).Hash.ToLower() -ne $hash)
   {
      $failures.Add("assets/branding/generated/$rel does not match manifest.txt")
   }
}
$logo = Join-Path $root 'src\gwt\src\org\rstudio\studio\client\workbench\views\superrstudio\superr-logo-96.png'
if ((Get-FileHash $logo).Hash -ne (Get-FileHash (Join-Path $root 'assets\branding\generated\png\superr-96.png')).Hash)
{
   $failures.Add('superr-logo-96.png in the GWT sources is not the generated 96 px icon')
}

if ($failures.Count -gt 0)
{
   $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }
   exit 1
}
Write-Host "Product identity consistent: $($product.productName) $($product.version)-$($product.prerelease)" -ForegroundColor Green
exit 0
