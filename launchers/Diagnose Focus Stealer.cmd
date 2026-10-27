@echo off
setlocal
title PES 2021 - find out what keeps stealing focus
echo Watch this window while you play. It lists every program that takes the
echo foreground and how many times, so the culprit can be identified.
echo.
echo Close the game first if it is already running with the fix - the fix
echo already prevents most stealing, so you would not see anything.
echo.
set /p SECS=How many seconds to watch [120]: 
if "%SECS%"=="" set SECS=120
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PES2021-Fullscreen.ps1" -Action Diagnose -DiagnoseSeconds %SECS%
echo.
pause
endlocal
