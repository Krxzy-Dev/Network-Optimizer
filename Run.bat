@echo off
setlocal EnableDelayedExpansion
title Network Cleaner and Optimiser

set "_PS1=%~dp0NetworkOptimizer.ps1"

if not exist "%_PS1%" (
    echo Cannot find NetworkOptimizer.ps1 next to this file. 1>&2
    echo Keep both files in the same folder. 1>&2
    pause
    exit /b 1
)

REM net session only works as admin, so it doubles as the admin check
net session >NUL 2>&1
if errorlevel 1 goto :elevate
goto :run

:elevate
echo Asking Windows for admin rights...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('\"' + $env:_PS1 + '\"')) -Verb RunAs"
if errorlevel 1 (
    echo You said no to the admin prompt, so nothing was run. 1>&2
    pause
    exit /b 1
)
exit /b 0

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%_PS1%" %*
set "_RC=%errorlevel%"
if not "%_RC%"=="0" echo Script stopped with code %_RC%. Check the log in %ProgramData%\NetworkOptimiser. 1>&2
pause
exit /b %_RC%
