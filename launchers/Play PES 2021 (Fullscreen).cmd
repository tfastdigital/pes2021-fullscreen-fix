@echo off
setlocal
title PES 2021 FULLSCREEN FIX - keep this window open while you play
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PES2021-Fullscreen.ps1" -Action Play %*
echo.
echo The game has closed.
timeout /t 6 >nul
endlocal
