# Security policy

## Supported versions

| Version | Supported |
| ------- | --------- |
| 1.1.x   | Yes       |
| 1.0.x   | Yes       |
| < 1.0   | No        |

Always test against the [latest release](https://github.com/tfastdigital6/pes2021-fullscreen-fix/releases/latest)
before reporting.

## Reporting a vulnerability

Report privately through either channel:

- GitHub: **Security** tab → **Report a vulnerability** (preferred, keeps the thread private)
- Telegram: https://t.me/tfasthub

Please include:

- The version shown in the window header and in the executable's file properties
- What the issue allows an attacker to do
- Steps to reproduce
- The log from `%TEMP%\PES2021Fullscreen.log` if relevant

Do not open a public issue for a vulnerability. Do not attach your own tokens, keys or personal
data.

Expect an initial reply within 7 days. Once a fix is available it ships in a patch release, and the
advisory is published after users have had time to update.

## Threat model

This tool edits per-user configuration and Windows settings, so the realistic risks are worth
stating plainly.

**What the program can do**

- Write to `Documents\KONAMI\eFootball PES 2021 SEASON UPDATE\settings.dat`
- Write to `HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers`
- Write to `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`
- Write to `HKCU\Control Panel\Desktop`, `HKCU\System\GameConfigStore` and Game Bar keys
- Extract `PES2021-Fullscreen.ps1` to `%LOCALAPPDATA%\TFastDigital\` and run it with Windows
  PowerShell
- Terminate known overlay processes belonging to the current user
- Start `PES2021.exe` from the detected game folder

**What it never does**

- No machine-wide (`HKLM`) writes, no services, no drivers
- No elevation unless you explicitly run `-DefenderExclusion` from an elevated window
- No executables written outside `%LOCALAPPDATA%\TFastDigital\`
- No code downloaded at run time; the engine is embedded in the executable
- No credentials, tokens or personal data read or transmitted

**Things to verify yourself**

- Compare the SHA-256 published on the release page with the file you downloaded:
  `Get-FileHash "PES 2021 TFast Fix.exe" -Algorithm SHA256`
- Read `src/PES2021-Fullscreen.ps1`. It is plain text and is the only code that modifies your
  system. The GUI is a thin front end around it.
- The optional update check fetches one static JSON file from GitHub Pages and sends no
  identifiers. Disable it with `-NoUpdateCheck`.
