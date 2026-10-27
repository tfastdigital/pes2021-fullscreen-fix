## What this changes

<!-- One or two sentences. Link the issue if there is one: Fixes #123 -->

## Why

<!-- The symptom or limitation being addressed. -->

## How it was tested

<!--
Be specific. Which GPU, which Windows build, what you did and what you saw.
State clearly if you could not test something, e.g. "no AMD hardware available".
-->

- [ ] `build/build-gui.ps1` completes and prints matching version metadata
- [ ] The affected button works in the GUI
- [ ] `-Action Restore` leaves the machine as it was
- [ ] Tested without a game folder (dummy `PES2021.exe`) where applicable

## Checklist

- [ ] Version bumped in `src/gui/TfastRunnerGui.cs`, `src/PES2021-Fullscreen.ps1` and `docs/version.json`
- [ ] `CHANGELOG.md` updated under the right heading
- [ ] No `HKLM` writes, no services, no elevation without an explicit documented option
- [ ] Any new registry or file change is saved before modification and undone by `Restore all`
- [ ] Comments explain the Windows behaviour involved, not just what the line does
