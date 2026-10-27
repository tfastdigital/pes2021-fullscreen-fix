@echo off
setlocal
title PES 2021 - use the strong GPU
echo This detects every graphics processor in this PC and makes PES 2021
echo always use the most powerful one (the discrete GPU when there are two).
echo.
echo It also shows which GPU the game is really rendering on right now.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PES2021-Fullscreen.ps1" -Action Gpu %*
echo.
pause
endlocal
