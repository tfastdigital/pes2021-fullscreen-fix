<#
.SYNOPSIS
    Creates the public GitHub repository, pushes this history, enables Pages and cuts the release.

.DESCRIPTION
    Run this once, after `gh auth login`. It is idempotent: re-running it pushes new commits and
    skips anything already done.

    Everything it changes is visible in the output, and it stops at the first problem instead of
    leaving the repository half-configured.

.PARAMETER Owner
    GitHub user or organisation. Defaults to tfastdigital.

.PARAMETER Repo
    Repository name. Defaults to pes2021-fullscreen-fix.

.PARAMETER Tag
    Release tag to create once the branch is pushed. Defaults to the version in docs/version.json
    prefixed with v. Pass -NoRelease to skip.

.EXAMPLE
    gh auth login
    powershell -ExecutionPolicy Bypass -File .\build\publish.ps1
#>
[CmdletBinding()]
param(
    [string]$Owner = 'tfastdigital',
    [string]$Repo = 'pes2021-fullscreen-fix',
    [string]$Tag,
    [switch]$NoRelease
)

$ErrorActionPreference = 'Stop'
if (-not $PSScriptRoot) { throw 'Run this script from disk.' }

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    # ---------------------------------------------------------------- tools
    $gh = @(
        (Get-Command gh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        (Join-Path $env:LOCALAPPDATA 'gh-cli2\gh.exe'),
        (Join-Path $env:LOCALAPPDATA 'gh-cli\bin\gh.exe'),
        'C:\Program Files\GitHub CLI\gh.exe'
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

    if (-not $gh) { throw 'GitHub CLI not found. Install it, or run the portable copy from PUBLISHING.md.' }

    function Invoke-Gh {
        param([string[]]$GhArgs)

        # gh writes ordinary diagnostics to stderr, which PowerShell turns into a terminating
        # NativeCommandError while $ErrorActionPreference is Stop. Run these calls with the
        # preference relaxed and read the exit code instead.
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $out = & $gh @GhArgs 2>&1 | Out-String
            $code = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previous
        }
        return [pscustomobject]@{ Output = $out.Trim(); Code = $code }
    }

    Write-Host "gh: $gh"

    $status = Invoke-Gh @('auth', 'status')
    if ($status.Code -ne 0) {
        Write-Host ''
        Write-Host 'Not signed in to GitHub.' -ForegroundColor Yellow
        Write-Host "Run this first, then re-run the script:`n"
        Write-Host "  & `"$gh`" auth login`n" -ForegroundColor Cyan
        exit 1
    }
    Write-Host 'Authentication: ok'

    # ---------------------------------------------------------------- repository
    $repoCheck = Invoke-Gh @('repo', 'view', "$Owner/$Repo")
    if ($repoCheck.Code -eq 0) {
        Write-Host "Repository $Owner/$Repo already exists."
    }
    else {
        Write-Host "Creating $Owner/$Repo (public)..."
        $create = Invoke-Gh @(
            'repo', 'create', "$Owner/$Repo",
            '--public',
            '--description', 'Fix eFootball PES 2021 dropping to the taskbar and running on the wrong GPU on Windows 10 and 11',
            '--homepage', "https://$($Owner.ToLower()).github.io/$Repo/"
        )
        if ($create.Code -ne 0) { throw "Could not create the repository: $($create.Output)" }
        Write-Host $create.Output
    }

    # ---------------------------------------------------------------- remote + push
    $remotes = (& git remote) 2>&1
    $url = "https://github.com/$Owner/$Repo.git"
    if ($remotes -contains 'origin') {
        & git remote set-url origin $url
    }
    else {
        & git remote add origin $url
    }
    Write-Host "Remote origin -> $url"

    Write-Host 'Pushing main...'
    & git push -u origin main
    if ($LASTEXITCODE -ne 0) { throw 'Push failed.' }

    # ---------------------------------------------------------------- pages
    $pages = Invoke-Gh @('api', "repos/$Owner/$Repo/pages")
    if ($pages.Code -ne 0) {
        Write-Host 'Enabling GitHub Pages (workflow build)...'
        $enable = Invoke-Gh @('api', '-X', 'POST', "repos/$Owner/$Repo/pages", '-f', 'build_type=workflow')
        if ($enable.Code -ne 0) { Write-Host "  Pages could not be enabled automatically: $($enable.Output)" -ForegroundColor Yellow }
        else { Write-Host '  Pages enabled.' -ForegroundColor Green }
    }
    else {
        Write-Host 'GitHub Pages already configured.'
    }

    # ---------------------------------------------------------------- release
    if (-not $NoRelease) {
        if (-not $Tag) {
            $feed = Get-Content (Join-Path $PSScriptRoot '..\docs\version.json') -Raw | ConvertFrom-Json
            $Tag = "v$($feed.version)"
        }

        $existing = Invoke-Gh @('release', 'view', $Tag)
        if ($existing.Code -eq 0) {
            Write-Host "Release $Tag already exists."
        }
        else {
            Write-Host "Pushing tag $Tag to trigger the release workflow..."
            & git tag $Tag 2>&1 | Out-Null
            & git push origin $Tag
            if ($LASTEXITCODE -ne 0) { throw 'Tag push failed.' }
        }
    }

    # ---------------------------------------------------------------- summary
    $site = "https://$($Owner.ToLower()).github.io/$Repo/"
    Write-Host ''
    Write-Host 'Done.' -ForegroundColor Green
    Write-Host "  Repository : https://github.com/$Owner/$Repo"
    Write-Host "  Actions    : https://github.com/$Owner/$Repo/actions"
    Write-Host "  Release    : https://github.com/$Owner/$Repo/releases"
    Write-Host "  Site       : $site"
    Write-Host ''
    Write-Host 'The build workflow attaches the executable to the release and updates the'
    Write-Host 'version feed that the app polls. Watch it with:'
    Write-Host "  & `"$gh`" run watch" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
