$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$piLauncher = Join-Path $scriptDir "..\PiAgent\pi-test.ps1"
$extension = Join-Path $scriptDir "godot-pat\index.ts"
$piTsconfig = Join-Path $scriptDir "..\PiAgent\tsconfig.json"

$originalDirectory = (Get-Location).Path
$gamesRoot = Join-Path $scriptDir "..\games"
$currentDirectory = [System.IO.Path]::GetFullPath($originalDirectory)
$gamesDirectory = [System.IO.Path]::GetFullPath($gamesRoot)
if (-not $currentDirectory.StartsWith($gamesDirectory + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    Set-Location -LiteralPath (Join-Path $gamesRoot "system")
}

$oldTsxConfig = $env:TSX_TSCONFIG_PATH
try {
    $env:TSX_TSCONFIG_PATH = $piTsconfig
    & $piLauncher --extension $extension @args
} finally {
    $env:TSX_TSCONFIG_PATH = $oldTsxConfig
    Set-Location -LiteralPath $originalDirectory
}
