param(
    [ValidateSet("Debug", "Release", "RelWithDebInfo", "MinSizeRel")]
    [string]$Configuration = "Release",
    [string]$BuildDir = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ProjectDir)

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot "work\windows-build"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RepoRoot "outputs\windows"
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

cmake -S $ProjectDir -B $BuildDir
cmake --build $BuildDir --config $Configuration

$CandidatePaths = @(
    (Join-Path $BuildDir "$Configuration\FocusVeil.exe"),
    (Join-Path $BuildDir "FocusVeil.exe")
)

$ExecutablePath = $CandidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ExecutablePath) {
    $ExecutablePath = Get-ChildItem -Path $BuildDir -Recurse -Filter "FocusVeil.exe" |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $ExecutablePath) {
    throw "FocusVeil.exe was not produced by the build."
}

$OutputExecutable = Join-Path $OutputDir "FocusVeil.exe"
Copy-Item -Force $ExecutablePath $OutputExecutable

Write-Host "Built $OutputExecutable"
