[CmdletBinding()]
param(
    [string]$Project,
    [Parameter(Mandatory = $true)][string]$Out,
    [ValidateRange(1, 100000)][int]$Frames = 30,
    [string]$Scene,
    [string]$Scenario,
    [string[]]$GameArgs = @(),
    [string]$Godot
)

$ErrorActionPreference = 'Stop'

if (-not $Project) {
    if (Test-Path -LiteralPath '.\project.godot' -PathType Leaf) { $Project = '.' }
    elseif (Test-Path -LiteralPath '.\game\project.godot' -PathType Leaf) { $Project = '.\game' }
    else { throw 'No Godot project in the current directory or game/. Use -Project for another directory.' }
}
$projectPath = (Resolve-Path -LiteralPath $Project).Path
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'project.godot') -PathType Leaf)) {
    throw "No project.godot found in: $projectPath"
}

if (-not $Godot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Godot = Join-Path $workspaceRoot 'Godot_Engine\Godot_v4.6.2-stable_win64_console.exe'
}
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)
$outputDirectory = [System.IO.Path]::GetDirectoryName($outputPath)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$captureDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("ltgd-screenshot-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $captureDirectory | Out-Null

try {
    $capturePath = Join-Path $captureDirectory 'frame.png'
    $captureScript = Join-Path $PSScriptRoot 'screenshot.gd'
    $godotArgs = @(
        '--path', $projectPath,
        '--display-driver', 'windows',
        '--rendering-driver', 'opengl3',
        '--audio-driver', 'Dummy',
        '--resolution', '1280x720',
        '--script', $captureScript,
        '--', '--out', $capturePath, '--frames', [string]$Frames
    )
    if ($Scene) { $godotArgs += @('--scene', $Scene) }
    if ($Scenario) { $godotArgs += @('--scenario', $Scenario) }
    if ($GameArgs) { $godotArgs += $GameArgs }

    $godotOutput = @(& $godotPath @godotArgs 2>&1)
    $exitCode = $LASTEXITCODE
    $godotOutput | ForEach-Object { Write-Output $_ }
    if ($exitCode -ne 0) { throw "Godot exited with code $exitCode" }
    if ($godotOutput | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' }) {
        throw 'Godot reported an error while capturing the screenshot.'
    }
    if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) { throw 'Godot produced no PNG screenshot.' }
    Copy-Item -LiteralPath $capturePath -Destination $outputPath -Force
    Write-Output "Screenshot saved: $outputPath"
}
finally {
    Get-ChildItem -LiteralPath $captureDirectory -File | Remove-Item -Force
    Remove-Item -LiteralPath $captureDirectory
}
