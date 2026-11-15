@echo off
rem Lance Preparation.ps1 avec les droits administrateur, sous Windows PowerShell 5.1.
rem Fonctionne depuis n'importe quel dossier : copie locale, dossier telecharge, partage reseau,
rem support amovible. Usage : Lancer.cmd [-Simulation ^| -Real]   (arguments transmis au script)
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "FP_LAUNCHER=%~f0"
set "FP_SCRIPT=%~dp0Preparation.ps1"
set "FP_ARGS=%*"

if exist "%FP_SCRIPT%" goto check_admin
echo.
echo Preparation.ps1 est introuvable a cote de Lancer.cmd :
echo   %FP_SCRIPT%
echo Si l'outil vient d'une archive ZIP, extrayez-la entierement avant de lancer.
echo.
pause
exit /b 1

:check_admin
net session >nul 2>&1
if %errorlevel% equ 0 goto run

rem Elevation. Le chemin et les arguments passent par des variables d'environnement : ils ne sont
rem jamais reinterpretes (apostrophe, espace, parenthese). Un lecteur reseau mappe n'existe pas
rem dans la session elevee : il est remplace par son chemin reseau complet.
"%PS%" -NoProfile -Command "$l = $env:FP_LAUNCHER; if ($l.Length -gt 3 -and $l.Substring(1, 2) -eq ':\') { $d = Get-PSDrive -Name $l.Substring(0, 1) -ErrorAction SilentlyContinue; if ($d -and $d.DisplayRoot -like '\\*') { $l = Join-Path $d.DisplayRoot $l.Substring(3) } }; $p = @{ FilePath = $l; Verb = 'RunAs' }; if ($env:FP_ARGS) { $p.ArgumentList = $env:FP_ARGS }; try { Start-Process @p } catch { Write-Host ('Elevation refusee ou impossible : ' + $_.Exception.Message); exit 1 }"
if %errorlevel% neq 0 pause
exit /b

:run
"%PS%" -NoProfile -ExecutionPolicy Bypass -STA -File "%FP_SCRIPT%" %*
if %errorlevel% neq 0 pause
