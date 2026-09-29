$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$piLauncher = Join-Path $scriptDir "..\PiAgent\pi-test.ps1"
$extension = Join-Path $scriptDir "godot-pat\index.ts"
$piTsconfig = Join-Path $scriptDir "..\PiAgent\tsconfig.json"

$oldTsxConfig = $env:TSX_TSCONFIG_PATH
try {
    $env:TSX_TSCONFIG_PATH = $piTsconfig
    & $piLauncher --extension $extension @args
} finally {
    $env:TSX_TSCONFIG_PATH = $oldTsxConfig
}
