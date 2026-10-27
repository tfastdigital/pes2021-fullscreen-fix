@echo off
setlocal
title PES 2021 FULLSCREEN FIX - one time repair
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PES2021-Fullscreen.ps1" -Action Fix -InstallStartup %*
echo.
timeout /t 10 >nul
endlocal
