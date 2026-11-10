@echo off
rem Lance Preparation.ps1 avec les droits administrateur, sous Windows PowerShell 5.1.
rem Usage : Lancer.cmd [-Simulation ^| -Real]   (les arguments sont transmis au script)
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

net session >nul 2>&1
if %errorlevel% neq 0 (
    if "%~1"=="" (
        "%PS%" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        "%PS%" -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Preparation.ps1" %*
if %errorlevel% neq 0 pause
