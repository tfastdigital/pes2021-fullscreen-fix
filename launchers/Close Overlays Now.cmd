@echo off
setlocal
title PES 2021 - close focus-stealing overlays
echo Closing known overlay apps (ScreenRec, Xbox Game Bar, NVIDIA/AMD/Overwolf,
echo RivaTuner, Fraps, Steam overlay helper)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PES2021-Fullscreen.ps1" -Action Overlays %*
echo.
timeout /t 8 >nul
endlocal
