@echo off
rem Lance Preparation.ps1 avec les droits administrateur.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Preparation.ps1"
if %errorlevel% neq 0 pause
