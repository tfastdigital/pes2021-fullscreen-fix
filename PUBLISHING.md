# Publishing this repository

The repository is prepared and committed. Only one step needs your GitHub account: signing in.
Tokens are never stored in this folder and never shared.

## One command each

```powershell
# 1. sign in once (opens the browser)
& "$env:LOCALAPPDATA\gh-cli2\gh.exe" auth login

# 2. create the repository, push, enable Pages, cut the release
powershell -ExecutionPolicy Bypass -File .\build\publish.ps1
```

`publish.ps1` is safe to re-run. It creates `tfastdigital6/pes2021-fullscreen-fix` only if it does
not exist, sets `origin`, pushes `main`, enables GitHub Pages with the workflow build type, and
pushes the version tag that triggers the release workflow. If Pages cannot be enabled through the
API it says so and you can turn it on in Settings.

Useful switches:

```powershell
# push only, no release
powershell -ExecutionPolicy Bypass -File .\build\publish.ps1 -NoRelease

# different owner or name
powershell -ExecutionPolicy Bypass -File .\build\publish.ps1 -Owner myorg -Repo myrepo
```

## What happens after the push

| Trigger              | Result                                                                                   |
| -------------------- | ---------------------------------------------------------------------------------------- |
| Push to `main`       | `build` workflow compiles the exe and checks the metadata                                |
| Change under `docs/` | `pages` workflow publishes the project page                                              |
| Push of a `v*` tag   | Release created with the exe attached, SHA-256 in the notes, `docs/version.json` updated |

Watch the first run with:

```powershell
& "$env:LOCALAPPDATA\gh-cli2\gh.exe" run watch
```

## Expected addresses

| Purpose      | Address                                                            |
| ------------ | ------------------------------------------------------------------ |
| Repository   | https://github.com/tfastdigital6/pes2021-fullscreen-fix             |
| Releases     | https://github.com/tfastdigital6/pes2021-fullscreen-fix/releases    |
| Project page | https://tfastdigital6.github.io/pes2021-fullscreen-fix/             |
| Update feed  | https://tfastdigital6.github.io/pes2021-fullscreen-fix/version.json |

The feed address is compiled into the application. If you publish under a different owner or name,
update `Brand.VersionFeed` and `Brand.ReleasesPage` in `src/gui/TfastRunnerGui.cs` before building,
otherwise the update check silently reports nothing.

## Finishing touches worth doing once

| Setting                         | Where                              | Value                                                                                |
| ------------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------ |
| Description and website         | Settings → General                 | Already set by `publish.ps1`, edit if needed                                         |
| Topics                          | Settings → General                 | `pes2021`, `efootball`, `fullscreen`, `windows-11`, `dxgi`, `powershell`, `winforms` |
| Discussions                     | Settings → General → Features      | Optional, useful for troubleshooting threads                                         |
| Private vulnerability reporting | Settings → Code security           | Enable so the link in `SECURITY.md` works                                            |
| Dependabot alerts               | Settings → Code security           | Enable                                                                               |
| Branch protection on `main`     | Settings → Branches                | Require the `build` check before merging                                             |
| Squash merge only               | Settings → General → Pull requests | Keeps history readable                                                               |

## Shipping an update later

```powershell
powershell -ExecutionPolicy Bypass -File .\build\set-version.ps1 -Version 1.2.0 -Notes "What changed"
# add a CHANGELOG.md entry, then
git commit -am "chore: release v1.2.0"
powershell -ExecutionPolicy Bypass -File .\build\publish.ps1
```

Existing installs then show one line: `Version 1.2.0 is available`, with a Download button.
Nothing is downloaded or executed automatically.

## Never committed

`build/*.exe`, `build/*.ico`, logs and screenshots are ignored. The binary is produced by CI and
attached to the release, so every download can be traced to a commit.
