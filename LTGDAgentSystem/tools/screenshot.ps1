[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$Out,
    [ValidateRange(1, 100000)][int]$Frames = 60,
    [string]$Scene,
    [string]$Scenario,
    [string[]]$GameArgs = @(),
    [string]$Godot
)

$ErrorActionPreference = 'Stop'

$projectPath = (Resolve-Path -LiteralPath $Project).Path
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'project.godot') -PathType Leaf)) {
    throw "No project.godot found in: $projectPath"
}

if (-not $Godot) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Godot = Join-Path $workspaceRoot 'Godot_Engine\Godot_v4.6.2-stable_win64_console.exe'
}
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$outputPath = [System.IO.Path]::GetFullPath($Out)
$outputDirectory = [System.IO.Path]::GetDirectoryName($outputPath)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$captureDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("ltgd-screenshot-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $captureDirectory | Out-Null

try {
    $moviePath = Join-Path $captureDirectory 'frame.png'
    $godotArgs = @('--path', $projectPath, '--write-movie', $moviePath, '--quit-after', [string]$Frames, '--fixed-fps', '60', '--disable-vsync')
    if ($Scene) { $godotArgs += @('--scene', $Scene) }

    $forwardedArgs = @()
    if ($Scenario) { $forwardedArgs += @('--scenario', $Scenario) }
    if ($GameArgs) { $forwardedArgs += $GameArgs }
    if ($forwardedArgs.Count -gt 0) { $godotArgs += @('--') + $forwardedArgs }

    $godotOutput = @(& $godotPath @godotArgs 2>&1)
    $exitCode = $LASTEXITCODE
    $godotOutput | ForEach-Object { Write-Output $_ }
    if ($exitCode -ne 0) { throw "Godot exited with code $exitCode" }
    if ($godotOutput | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' }) {
        throw 'Godot reported an error while recording the screenshot.'
    }

    $lastFrame = Get-ChildItem -LiteralPath $captureDirectory -File |
        Where-Object { $_.Name -match '^frame\d{8}\.png$' } |
        Sort-Object Name |
        Select-Object -Last 1
    if (-not $lastFrame) { throw 'Godot produced no PNG frames.' }

    Copy-Item -LiteralPath $lastFrame.FullName -Destination $outputPath -Force
    Write-Output "Screenshot saved: $outputPath"
}
finally {
    Get-ChildItem -LiteralPath $captureDirectory -File | Remove-Item -Force
    Remove-Item -LiteralPath $captureDirectory
}
