<#
.SYNOPSIS
    Compiles "PES 2021 TFast Fix.exe" from src/gui/TfastRunnerGui.cs.

.DESCRIPTION
    The fix engine (src/PES2021-Fullscreen.ps1) and the application icon are embedded as
    resources, so the result is one self-contained executable.

    The build fails if the version metadata is missing or inconsistent, which prevents
    shipping a binary that reports the wrong version to the update check.

.PARAMETER Configuration
    Release (default) or Debug (keeps optimisations off and emits a pdb).

.PARAMETER OutputDir
    Where to write the executable. Defaults to build\.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build\build-gui.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',

    # Left empty on purpose: $PSScriptRoot is not populated yet inside the param block.
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

if (-not $PSScriptRoot) { throw 'Run this script from disk, for example: powershell -File .\build\build-gui.ps1' }
if (-not $OutputDir) { $OutputDir = $PSScriptRoot }

$repoRoot = Split-Path -Parent $PSScriptRoot

$source = Join-Path $repoRoot 'src\gui\TfastRunnerGui.cs'
$engine = Join-Path $repoRoot 'src\PES2021-Fullscreen.ps1'
$icon = Join-Path $PSScriptRoot 'tfast.ico'
$output = Join-Path $OutputDir 'PES 2021 TFast Fix.exe'

foreach ($required in @($source, $engine)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing required file: $required" }
}

# The icon is generated, not committed, so recreate it when absent.
if (-not (Test-Path -LiteralPath $icon)) {
    $iconMaker = Join-Path $PSScriptRoot 'make-icon.ps1'
    if (-not (Test-Path -LiteralPath $iconMaker)) { throw 'tfast.ico is missing and make-icon.ps1 was not found.' }
    Write-Host 'Generating icon...'
    & $iconMaker -Out $icon | Out-Null
}

$csc = @(
    "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $csc) { throw 'csc.exe was not found. .NET Framework 4.x is required.' }

# Version consistency: the C# assembly attributes and the engine header must agree.
$csText = Get-Content -LiteralPath $source -Raw
$match = [regex]::Match($csText, 'AssemblyVersion\("(\d+\.\d+\.\d+)\.0"\)')
if (-not $match.Success) { throw 'AssemblyVersion attribute not found in TfastRunnerGui.cs' }
$version = $match.Groups[1].Value

$engineMatch = [regex]::Match((Get-Content -LiteralPath $engine -Raw), 'Version:\s*(\d+\.\d+\.\d+)')
$engineVersion = if ($engineMatch.Success) { $engineMatch.Groups[1].Value } else { 'unknown' }

if ($engineVersion -ne 'unknown' -and $engineVersion -ne $version) {
    throw "Version mismatch: GUI reports $version but the engine header reports $engineVersion"
}

if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }

Write-Host "Version  : $version"
Write-Host "Compiler : $csc"
Write-Host "Engine   : $engine"
Write-Host ''

$cscArgs = @(
    '/nologo',
    '/target:winexe',
    "/out:$output",
    '/platform:anycpu',
    "/resource:$engine,PES2021-Fullscreen.ps1",
    "/resource:$icon,tfast.ico",
    "/win32icon:$icon",
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll'
)

if ($Configuration -eq 'Release') {
    $cscArgs += '/optimize+'
}
else {
    $cscArgs += @('/optimize-', '/debug+', '/define:DEBUG')
}

$cscArgs += $source

& $csc $cscArgs
if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $output)) { throw 'Build produced no output file.' }

$info = Get-Item -LiteralPath $output
$fv = $info.VersionInfo
$hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash

Write-Host ''
Write-Host ("Built    : {0}" -f $info.FullName) -ForegroundColor Green
Write-Host ("Size     : {0:N0} bytes" -f $info.Length)
Write-Host ("Company  : {0}" -f $fv.CompanyName)
Write-Host ("Product  : {0}" -f $fv.ProductName)
Write-Host ("Version  : {0}" -f $fv.FileVersion)
Write-Host ("SHA256   : {0}" -f $hash)
Write-Host ''

if ($fv.CompanyName -notmatch 'TFast') { throw 'Branding metadata missing from the built executable.' }
if ($fv.FileVersion -notlike "$version*") { throw "Built version $($fv.FileVersion) does not match expected $version" }

Write-Host 'Metadata verified.' -ForegroundColor Green
Write-Host $output
