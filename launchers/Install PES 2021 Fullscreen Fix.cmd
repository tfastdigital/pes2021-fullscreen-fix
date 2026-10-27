@echo off
setlocal
set "ENGINE=%~dp0..\src\PES2021-Fullscreen.ps1"

if not exist "%ENGINE%" (
    echo Engine not found: %ENGINE%
    echo Run this from a clone of the repository.
    pause
    exit /b 1
)

title PES 2021 Fullscreen Fix - install
echo Applying the fix and enabling it to start with Windows.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Action Fix -InstallStartup %*
echo.
timeout /t 10 >nul
endlocal
