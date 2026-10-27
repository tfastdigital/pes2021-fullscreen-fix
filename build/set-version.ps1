<#
.SYNOPSIS
    Sets the version in every file that records it, then verifies they agree.

.DESCRIPTION
    The version lives in three places:

      src/gui/TfastRunnerGui.cs    AssemblyVersion, AssemblyFileVersion, Brand.Version
      src/PES2021-Fullscreen.ps1   header .NOTES line
      docs/version.json            version, date, url

    Forgetting one of them makes the update check lie to users, so this script writes
    all three and fails if the result is inconsistent.

.PARAMETER Version
    Semantic version, for example 1.2.0. A leading v is accepted and stripped.

.PARAMETER Notes
    One-line summary written into docs/version.json.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build\set-version.ps1 -Version 1.2.0 -Notes "Overlay schedule option"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'

if (-not $PSScriptRoot) { throw 'Run this script from disk.' }
$repoRoot = Split-Path -Parent $PSScriptRoot

$Version = $Version.TrimStart('v', 'V')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "'$Version' is not a semantic version (expected MAJOR.MINOR.PATCH)." }

$gui = Join-Path $repoRoot 'src\gui\TfastRunnerGui.cs'
$engine = Join-Path $repoRoot 'src\PES2021-Fullscreen.ps1'
$feed = Join-Path $repoRoot 'docs\version.json'

foreach ($f in @($gui, $engine, $feed)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "Missing file: $f" }
}

# ---- GUI
$text = Get-Content -LiteralPath $gui -Raw
$text = [regex]::Replace($text, 'AssemblyVersion\("\d+\.\d+\.\d+\.0"\)', "AssemblyVersion(`"$Version.0`")")
$text = [regex]::Replace($text, 'AssemblyFileVersion\("\d+\.\d+\.\d+\.0"\)', "AssemblyFileVersion(`"$Version.0`")")
$text = [regex]::Replace($text, 'public const string Version\s*=\s*"\d+\.\d+\.\d+"', "public const string Version  = `"$Version`"")
Set-Content -LiteralPath $gui -Value $text -NoNewline

# ---- engine
$text = Get-Content -LiteralPath $engine -Raw
$text = [regex]::Replace($text, '(?m)^(\s*)Version:\s*\d+\.\d+\.\d+\s*$', "`$1Version: $Version")
Set-Content -LiteralPath $engine -Value $text -NoNewline

# ---- version feed
$data = Get-Content -LiteralPath $feed -Raw | ConvertFrom-Json
$data.version = $Version
$data.date = (Get-Date -Format 'yyyy-MM-dd')
if ($Notes) { $data.notes = $Notes }
$data.url = "https://github.com/tfastdigital6/pes2021-fullscreen-fix/releases/tag/v$Version"
$data | ConvertTo-Json | Set-Content -LiteralPath $feed -Encoding utf8

# ---- verify
$guiText = Get-Content -LiteralPath $gui -Raw
$engineText = Get-Content -LiteralPath $engine -Raw
$feedData = Get-Content -LiteralPath $feed -Raw | ConvertFrom-Json

$checks = @(
    @{ Name = 'AssemblyVersion'; Ok = $guiText -match "AssemblyVersion\(`"$([regex]::Escape($Version))\.0`"\)" }
    @{ Name = 'Brand.Version'; Ok = $guiText -match "Version\s*=\s*`"$([regex]::Escape($Version))`"" }
    @{ Name = 'engine header'; Ok = $engineText -match "(?m)^\s*Version:\s*$([regex]::Escape($Version))\s*$" }
    @{ Name = 'version.json'; Ok = $feedData.version -eq $Version }
)

$failed = @($checks | Where-Object { -not $_.Ok })
foreach ($c in $checks) {
    '{0}  {1}' -f $(if ($c.Ok) { 'ok  ' } else { 'FAIL' }), $c.Name
}
if ($failed.Count -gt 0) { throw 'Version update incomplete.' }

Write-Host ''
Write-Host "Version set to $Version" -ForegroundColor Green
Write-Host 'Next:'
Write-Host "  1. Add a CHANGELOG.md entry for $Version"
Write-Host "  2. git commit -am `"chore: release v$Version`""
Write-Host "  3. git tag v$Version; git push origin main --tags"
