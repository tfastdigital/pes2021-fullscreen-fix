# Publishing this repository

Everything is prepared and committed locally. These are the only steps that need your GitHub
account, because creating a repository and pushing require your credentials. No tokens are stored
in this folder.

## 1. Sign in to GitHub CLI

Git and GitHub CLI are installed. `gh` lives at `%LOCALAPPDATA%\gh-cli\bin\gh.exe` (portable copy,
used because the MSI needs elevation). Open a new PowerShell window and run:

```powershell
& "$env:LOCALAPPDATA\gh-cli\bin\gh.exe" auth login
```

Choose **GitHub.com**, **HTTPS**, and authenticate in the browser. Sign in as the account that owns
the `tfastdigital` namespace, or create that organisation first.

## 2. Create the repository and push

From this folder:

```powershell
& "$env:LOCALAPPDATA\gh-cli\bin\gh.exe" repo create tfastdigital/pes2021-fullscreen-fix `
    --public `
    --description "Fix eFootball PES 2021 dropping to the taskbar and running on the wrong GPU on Windows 10 and 11" `
    --homepage "https://tfastdigital.github.io/pes2021-fullscreen-fix/" `
    --source . `
    --remote origin `
    --push
```

If you would rather use the website: create an empty public repo named
`pes2021-fullscreen-fix` under `tfastdigital`, then run

```powershell
git remote add origin https://github.com/tfastdigital/pes2021-fullscreen-fix.git
git push -u origin main
```

## 3. Enable GitHub Pages

Pages must be switched on once. The workflow cannot do it for you.

1. Repository → **Settings** → **Pages**
2. **Build and deployment** → Source: **GitHub Actions**
3. Re-run the `pages` workflow, or push any change to `docs/`

The site appears at `https://tfastdigital.github.io/pes2021-fullscreen-fix/`, which is the address
the app already polls for updates.

## 4. Publish the first release

```powershell
git tag v1.1.0
git push origin main --tags
```

The `build` workflow then compiles the executable on a clean Windows runner, verifies the version
metadata, attaches `PES 2021 TFast Fix.exe` to the release, records its SHA-256 in the release notes
and updates `docs/version.json`.

Watch progress with:

```powershell
& "$env:LOCALAPPDATA\gh-cli\bin\gh.exe" run list --limit 5
& "$env:LOCALAPPDATA\gh-cli\bin\gh.exe" run watch
```

## 5. Recommended repository settings

| Setting | Where | Value |
| --- | --- | --- |
| Description and website | Settings → General | Use the values from step 2 |
| Topics | Settings → General | `pes2021`, `efootball`, `fullscreen`, `windows-11`, `dxgi`, `powershell`, `winforms` |
| Discussions | Settings → General → Features | Optional, useful for troubleshooting threads |
| Private vulnerability reporting | Settings → Code security | Enable, so `SECURITY.md` links work |
| Dependabot alerts | Settings → Code security | Enable |
| Branch protection on `main` | Settings → Branches | Require the `build` check to pass before merging |
| Squash merge only | Settings → General → Pull requests | Keeps history readable |

## 6. After a release

- Users on an older build see a single line in the app: `Version X is available`, with a Download
  button pointing at the release page. Nothing is downloaded automatically.
- To ship a change, run `build\set-version.ps1 -Version 1.2.0`, add a `CHANGELOG.md` entry, commit,
  tag and push. The script writes and verifies all three version locations.

## Files that must never be committed

`build/*.exe`, `build/*.ico`, logs and screenshots are ignored by `.gitignore`. The executable is
produced by CI and attached to the release, not tracked, so the repository stays small and every
binary can be traced to a commit.
