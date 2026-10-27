# Contributing

Thanks for taking the time to improve this project. Bug reports are as valuable as code, because
every symptom here depends on the specific machine it happens on.

## Before you open an issue

1. Run **Diagnose focus** in the application, or
   `powershell -ExecutionPolicy Bypass -File .\src\PES2021-Fullscreen.ps1 -Action Diagnose`.
2. Run **Restore all** and apply the fix again. This clears stale state.
3. Collect the log: `%TEMP%\PES2021Fullscreen.log`.
4. Note your GPU, driver version, Windows build (`winver`) and display scaling.

Use the bug report template. Reports without a log and GPU details usually cannot be reproduced.

## Reporting a security issue

Do not open a public issue. Follow [SECURITY.md](SECURITY.md).

## Development setup

Requirements:

- Windows 10 or 11
- .NET Framework 4.x (for `csc.exe`)
- PowerShell 5.1 (Windows PowerShell, not PowerShell 7) for the engine
- .NET SDK only if you want to use an editor with IntelliSense

```powershell
git clone https://github.com/tfastdigital/pes2021-fullscreen-fix.git
cd pes2021-fullscreen-fix
powershell -ExecutionPolicy Bypass -File .\build\build-gui.ps1
```

The build writes `build\PES 2021 TFast Fix.exe` and prints its version metadata. A branding or
version mismatch aborts the build.

### Testing without a real game

The engine accepts `-GameDir`. Point it at a folder containing a dummy `PES2021.exe` and it will
exercise detection, logging and restore paths without touching a real installation:

```powershell
$tmp = "$env:TEMP\pes-test"; New-Item -ItemType Directory $tmp -Force | Out-Null
Set-Content "$tmp\PES2021.exe" ''
powershell -ExecutionPolicy Bypass -File .\src\PES2021-Fullscreen.ps1 -Action Fix -GameDir $tmp
powershell -ExecutionPolicy Bypass -File .\src\PES2021-Fullscreen.ps1 -Action Restore -GameDir $tmp
```

Always run `-Action Restore` afterwards so your own machine is left as you found it.

### Verifying the GUI

Clicking buttons by hand is slow. The window can be driven without a mouse:

- Buttons are found with `EnumChildWindows` + `GetWindowText`, then invoked with
  `SendMessage(hwnd, 0x00F5, 0, 0)` (`BM_CLICK`).
- The window can be captured regardless of z-order with
  `PrintWindow(hwnd, hdc, 2)` (`PW_RENDERFULLCONTENT`).
- Custom-painted buttons do **not** expose UI Automation's `InvokePattern`, and a busy desktop can
  refuse window activation. `BM_CLICK` avoids both problems.

## Coding conventions

**PowerShell (`src/PES2021-Fullscreen.ps1`)**

- Target PowerShell 5.1. No `??`, no ternary `? :`, no `-Parallel`.
- Every user-visible change goes through `Write-Ok`, `Write-Warn` or `Write-Fail` so the GUI log
  stays colour-coded.
- Save the previous value of anything you modify, in `%LOCALAPPDATA%\PES2021FullscreenFix\`, and
  restore it in `Undo-All`. Never leave the machine in a state that cannot be reverted.
- Prefer one combined condition over repeated registry reads, e.g.
  `if ([PesFix]::ForegroundShowsUserLeft() -and ($gameHadFocus -or (Get-Date) -gt $graceUntil))`.
- Never touch anything outside the current user's profile unless the option is explicitly
  documented as needing elevation.

**C# (`src/gui/TfastRunnerGui.cs`)**

- The compiler is the .NET Framework 4.x in-box `csc.exe`, which is **C# 5**. No string
  interpolation, no expression-bodied members, no `nameof`.
- Interface text is sentence case and factual. Avoid marketing words, badges, gradients and
  decorative glyphs; the design is deliberately flat.
- All engine output is streamed through `OutputDataReceived` and marshalled with `BeginInvoke`.
  Never block the UI thread on a child process.

**Commits**

Conventional Commits, imperative mood, one logical change per commit:

```text
fix: release foreground lock during watchdog restore
feat: add update check against GitHub Pages
docs: document the extra overlay option
```

## Release procedure

1. Update the version in three places:
   - `src/PES2021-Fullscreen.ps1` — header comment
   - `src/gui/TfastRunnerGui.cs` — `AssemblyVersion`, `AssemblyFileVersion`, `Brand.Version`
   - `docs/version.json` — `version`, `url`, `notes`, `date`
2. Add a `CHANGELOG.md` entry.
3. Commit, then tag and push:

   ```powershell
   git commit -am "chore: release v1.1.0"
   git tag v1.1.0
   git push origin main --tags
   ```

4. The `build` workflow compiles the executable, verifies metadata, attaches it to the release and
   deploys the project page. Confirm both jobs are green before announcing the release.

Version numbers are plain semver without a `v` prefix in `version.json`; the git tag keeps the `v`.
