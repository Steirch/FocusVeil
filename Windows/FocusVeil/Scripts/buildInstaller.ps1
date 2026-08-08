param(
    [ValidateSet("Debug", "Release", "RelWithDebInfo", "MinSizeRel")]
    [string]$Configuration = "Release",
    [string]$BuildDir = "",
    [string]$OutputDir = "",
    [string]$InnoCompiler = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$ProjectDir = Split-Path -Parent $ScriptDir
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ProjectDir)
$BuildScript = Join-Path $ScriptDir "build.ps1"
$InstallerScript = Join-Path $ProjectDir "Installer\FocusVeil.iss"
$SourceFile = Join-Path $ProjectDir "src\main.cpp"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RepoRoot "outputs\windows"
}

function Find-InnoCompiler {
    param([string]$ConfiguredPath)

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        if (Test-Path $ConfiguredPath) {
            return (Resolve-Path $ConfiguredPath).Path
        }
        throw "The configured Inno Setup compiler was not found: $ConfiguredPath"
    }

    $Command = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($Command) {
        return $Command.Source
    }

    $ProgramFiles = [Environment]::GetEnvironmentVariable("ProgramFiles")
    $ProgramFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $Candidates = @()
    if ($ProgramFilesX86) {
        $Candidates += Join-Path $ProgramFilesX86 "Inno Setup 7\ISCC.exe"
        $Candidates += Join-Path $ProgramFilesX86 "Inno Setup 6\ISCC.exe"
    }
    if ($ProgramFiles) {
        $Candidates += Join-Path $ProgramFiles "Inno Setup 7\ISCC.exe"
        $Candidates += Join-Path $ProgramFiles "Inno Setup 6\ISCC.exe"
    }

    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate) {
            return $Candidate
        }
    }

    throw "Inno Setup was not found. Install Inno Setup or pass -InnoCompiler with the ISCC.exe path."
}

$VersionMatch = Select-String `
    -Path $SourceFile `
    -Pattern 'kAppVersion\[\] = L"([^"]+)"' |
    Select-Object -First 1
if (-not $VersionMatch) {
    throw "Could not read the FocusVeil version from $SourceFile"
}
$Version = $VersionMatch.Matches[0].Groups[1].Value

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    & $BuildScript -Configuration $Configuration -OutputDir $OutputDir
} else {
    & $BuildScript -Configuration $Configuration -BuildDir $BuildDir -OutputDir $OutputDir
}

$CompilerPath = Find-InnoCompiler -ConfiguredPath $InnoCompiler
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

& $CompilerPath `
    "/DAppVersion=$Version" `
    "/DSourceDir=$OutputDir" `
    "/DOutputDir=$OutputDir" `
    $InstallerScript

if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE"
}

$InstallerPath = Join-Path $OutputDir "FocusVeilSetup.exe"
if (-not (Test-Path $InstallerPath)) {
    throw "FocusVeilSetup.exe was not produced by the installer build."
}

Write-Host "Built $InstallerPath"
