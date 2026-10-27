# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-10-27

### Added

- Optional update check against `version.json` on GitHub Pages, shown as a single line with a link
  to the release. Disabled with `-NoUpdateCheck`.
- GitHub Actions pipeline that builds the executable, verifies version metadata, publishes a
  release on tag and deploys the project page.
- Project page hosted on GitHub Pages with download link, feature summary and troubleshooting.

### Changed

- Interface rebuilt with a restrained design: neutral greys, one accent colour, hairlines, plain
  button labels in sentence case.
- Social links now use vector brand marks drawn with GDI+, removing the dependency on emoji fonts
  or external image files.

### Fixed

- Social captions clipped to "Telegra" and "WhatsA" at narrow widths.
- Light-themed system scrollbar visible against the dark log panel.

## [1.0.0] - 2026-10-27

### Added

- Fullscreen fix engine: `settings.dat` mode and resolution, fullscreen optimisation and DPI
  compatibility flags, per-user game settings with automatic backup.
- GPU selection through DXGI adapter enumeration with integrated / discrete / virtual
  classification, plus live verification against GPU engine performance counters.
- Focus protection through `ForegroundLockTimeout`, with automatic release during watchdog
  restores.
- Overlay control for ScreenRec, Xbox Game Bar, NVIDIA, AMD, Overwolf, RivaTuner, Fraps and the
  Steam overlay helper, with periodic re-checks and logging throttled for repeat offenders.
- Fullscreen watchdog that restores an involuntarily minimised game while respecting deliberate
  Alt+Tab, Win key and taskbar clicks.
- `Diagnose` mode that reports which process takes the foreground.
- Windows Forms front end with buttons, live log panel, progress indicator and stop button.
- One-button restore of every change, including Game Bar, notification and antivirus state.

[Unreleased]: https://github.com/tfastdigital6/pes2021-fullscreen-fix/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/tfastdigital6/pes2021-fullscreen-fix/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/tfastdigital6/pes2021-fullscreen-fix/releases/tag/v1.0.0
