@echo off
setlocal
set "ENGINE=%~dp0..\src\PES2021-Fullscreen.ps1"

if not exist "%ENGINE%" (
    echo Engine not found: %ENGINE%
    echo Run this from a clone of the repository.
    pause
    exit /b 1
)

title PES 2021 Fullscreen Fix
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Action Play %*
echo.
echo The game has closed.
timeout /t 6 >nul
endlocal
