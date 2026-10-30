<#
.SYNOPSIS
   Merge the SuperRStudio VS Code tasks/launch configurations into the local,
   Git-ignored .vscode/tasks.json and .vscode/launch.json.
   SPDX-License-Identifier: AGPL-3.0-only

.DESCRIPTION
   Upstream ignores .vscode/tasks.json and launch.json and ships templates in
   .vscode/open-source/. This script starts from that template when a local
   file does not exist, then inserts (or refreshes) the block between the
   "// >>> superrstudio" and "// <<< superrstudio" markers taken from
   .vscode/superrstudio/. Everything outside the markers is left untouched, and
   the previous file is kept as *.bak. Text-based so JSONC comments survive.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

. (Join-Path $PSScriptRoot 'dev-common.ps1')
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pattern = '(?s)[ \t]*// >>> superrstudio.*?// <<< superrstudio[ \t]*\r?\n'

foreach ($item in @(@{ File = 'tasks.json'; Key = '"tasks": [' }, @{ File = 'launch.json'; Key = '"configurations": [' }))
{
   $target = Join-Path $SrsRoot ".vscode\$($item.File)"
   $source = [IO.File]::ReadAllText((Join-Path $SrsRoot ".vscode\superrstudio\$($item.File)"))
   $block = [regex]::Match($source, $pattern).Value
   if (-not $block) { throw "No superrstudio block in .vscode/superrstudio/$($item.File)" }

   $text = if (Test-Path $target) { [IO.File]::ReadAllText($target) }
           else { [IO.File]::ReadAllText((Join-Path $SrsRoot ".vscode\open-source\$($item.File)")) }

   # keep the target's newline style (the upstream templates use CRLF)
   $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
   $block = $block -replace "`r?`n", $nl

   if ([regex]::IsMatch($text, $pattern))
   {
      $merged = [regex]::Replace($text, $pattern, { param($m) $block })
   }
   else
   {
      $index = $text.IndexOf($item.Key)
      if ($index -lt 0) { throw "Cannot find $($item.Key) in $target; merge .vscode/superrstudio/$($item.File) by hand." }
      $index += $item.Key.Length
      $merged = $text.Substring(0, $index) + $nl + $block.TrimEnd("`r", "`n") + $text.Substring($index)
   }

   if ($merged -eq $text) { Write-SrsStep "$target already up to date"; continue }
   if ($PSCmdlet.ShouldProcess($target, 'Merge SuperRStudio configurations'))
   {
      if (Test-Path $target) { Copy-Item $target "$target.bak" -Force }
      [IO.File]::WriteAllText($target, $merged, $utf8)
      Write-SrsStep "Updated $target"
   }
}
