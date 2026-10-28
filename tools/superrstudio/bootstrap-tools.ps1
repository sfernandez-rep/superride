# Portable build drivers only. System prerequisites remain upstream's responsibility.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$toolsRoot = Join-Path $repoRoot '.cache\superrstudio\tools'
New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null

$archives = @(
    @{
        Name = 'cmake-4.3.4-windows-x86_64.zip'
        Url = 'https://github.com/Kitware/CMake/releases/download/v4.3.4/cmake-4.3.4-windows-x86_64.zip'
        Hash = '86e5fcafb38bdf58346a78b187c7b6b4f252ae5242cffe24c463a92bbd2e77d1'
        Destination = $toolsRoot
        Executable = 'cmake-4.3.4-windows-x86_64\bin\cmake.exe'
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
