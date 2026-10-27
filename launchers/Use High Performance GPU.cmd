@echo off
setlocal
set "ENGINE=%~dp0..\src\PES2021-Fullscreen.ps1"

if not exist "%ENGINE%" (
    echo Engine not found: %ENGINE%
    pause
    exit /b 1
)

title PES 2021 Fullscreen Fix - GPU
echo Detecting graphics processors and selecting the high-performance one.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Action Gpu %*
echo.
pause
endlocal
