@echo off
setlocal
set "ENGINE=%~dp0..\src\PES2021-Fullscreen.ps1"

if not exist "%ENGINE%" (
    echo Engine not found: %ENGINE%
    pause
    exit /b 1
)

title PES 2021 Fullscreen Fix - overlays
echo Closing known overlay processes: ScreenRec, Xbox Game Bar, NVIDIA, AMD,
echo Overwolf, RivaTuner, Fraps and the Steam overlay helper.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Action Overlays %*
echo.
timeout /t 8 >nul
endlocal
