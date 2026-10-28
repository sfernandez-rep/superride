param(
    [ValidateSet('Index', 'Explain', 'Path', 'Query', 'Version')]
    [string]$Action = 'Version',
    [string[]]$Terms = @()
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$python = Join-Path $projectRoot '.cache\superrstudio\graphify-venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    throw 'Graphify is not provisioned. See docs/superrstudio/graphify.md for the reviewed installation.'
}
$graphRoot = Join-Path $projectRoot '.cache\superrstudio\graphify-source'
$graphFile = Join-Path $graphRoot 'graphify-out\graph.json'
$previousBackend = $env:GRAPHIFY_BACKEND
$previousRefresh = $env:GRAPHIFY_NO_AUTO_REFRESH
try {
    $env:GRAPHIFY_BACKEND = 'none'
    $env:GRAPHIFY_NO_AUTO_REFRESH = '1'
    switch ($Action) {
        'Index' { $cli = @('extract', (Join-Path $projectRoot 'src'), '--code-only', '--max-workers', '4', '--out', $graphRoot) }
        'Version' { $cli = @('--version') }
        default { $cli = @($Action.ToLowerInvariant()) + $Terms + @('--graph', $graphFile) }
    }
    & $python -m graphify @cli
    if ($LASTEXITCODE -ne 0) { throw "Graphify exited with code $LASTEXITCODE" }
} finally {
    $env:GRAPHIFY_BACKEND = $previousBackend
    $env:GRAPHIFY_NO_AUTO_REFRESH = $previousRefresh
}
