@echo off
setlocal
set "ENGINE=%~dp0..\src\PES2021-Fullscreen.ps1"

if not exist "%ENGINE%" (
    echo Engine not found: %ENGINE%
    pause
    exit /b 1
)

title PES 2021 Fullscreen Fix - focus diagnostics
echo Watching the foreground window to find any process that takes focus.
echo Leave this running while you play, then read the summary.
echo.
set /p SECS=How many seconds to watch [120]: 
if "%SECS%"=="" set SECS=120
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Action Diagnose -DiagnoseSeconds %SECS%
echo.
pause
endlocal
