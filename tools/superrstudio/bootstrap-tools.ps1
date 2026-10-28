# Portable build drivers only. System prerequisites remain upstream's responsibility.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$toolsRoot = Join-Path $repoRoot '.cache\superrstudio\tools'
New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null

$archives = @(
    @{
        Name = 'cmake-3.31.10-windows-x86_64.zip'
        Url = 'https://github.com/Kitware/CMake/releases/download/v3.31.10/cmake-3.31.10-windows-x86_64.zip'
        Hash = '13d1a463d7130df5339baedd63d8ae990aaf385062b2f42f372796143ae94086'
        Destination = $toolsRoot
        Executable = 'cmake-3.31.10-windows-x86_64\bin\cmake.exe'
    },
    @{
        Name = 'ninja-win.zip'
        Url = 'https://github.com/ninja-build/ninja/releases/download/v1.13.1/ninja-win.zip'
        Hash = '26a40fa8595694dec2fad4911e62d29e10525d2133c9a4230b66397774ae25bf'
        Destination = (Join-Path $toolsRoot 'ninja-1.13.1')
        Executable = 'ninja-1.13.1\ninja.exe'
    }
)

foreach ($archive in $archives) {
    $download = Join-Path $toolsRoot $archive.Name
    if (-not (Test-Path -LiteralPath $download)) {
        Invoke-WebRequest -UseBasicParsing -Uri $archive.Url -OutFile $download
    }
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $archive.Hash) {
        throw "SHA-256 mismatch: $download. Do not execute or extract this archive."
    }
    $executable = Join-Path $toolsRoot $archive.Executable
    if (-not (Test-Path -LiteralPath $executable)) {
        Expand-Archive -LiteralPath $download -DestinationPath $archive.Destination -Force
    }
    & $executable --version
    if ($LASTEXITCODE -ne 0) { throw "Tool verification failed: $executable" }
    $env:PATH = "$(Split-Path -Parent $executable);$env:PATH"
}

Write-Host 'Portable CMake and Ninja are on PATH for this PowerShell process.'
Write-Host 'MSVC 145, the Windows SDK, R, JDK 17, Ant and upstream dependencies are still required.'
