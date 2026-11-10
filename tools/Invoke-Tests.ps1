<#
    Lance les tests Pester (poste de développement uniquement, jamais sur la clé).
    Pester 5 est requis : Windows 11 n'embarque que Pester 3.4, à la syntaxe incompatible.
      Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5 -SkipPublisherCheck
    ou, sans installation : -PesterPath <dossier contenant Pester.psd1>.

    Usage : tools\Invoke-Tests.ps1 [-PesterPath <chemin>] [-Coverage]
#>
[CmdletBinding()]
param(
    [string]$PesterPath,
    [switch]$Coverage
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if ($PesterPath) {
    Import-Module (Join-Path $PesterPath 'Pester.psd1') -Force
} else {
    try { Import-Module Pester -MinimumVersion 5.0 -Force }
    catch { throw "Pester 5 introuvable. Installez-le : Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5 -SkipPublisherCheck (ou utilisez -PesterPath)." }
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $root 'tests'
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Normal'
if ($Coverage) {
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = @(
        (Join-Path $root 'src\FastPrepare.Core'),
        (Join-Path $root 'src\FastPrepare.Application')
    )
    $configuration.CodeCoverage.OutputPath = Join-Path $root 'tools\out\coverage.xml'
}
Invoke-Pester -Configuration $configuration
