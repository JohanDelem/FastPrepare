#Requires -Version 5.1
<#
    Outil de préparation de poste — point d'entrée.
    Lancement : Lancer.cmd (droits administrateur, Windows PowerShell 5.1, -STA).
    Ce fichier ne contient que l'ordre de démarrage ; l'architecture est décrite dans
    docs/architecture_plan.md.

    Usage : Lancer.cmd [-Simulation | -Real]
      sans paramètre : mode défini par Execution.DefaultMode dans config.json.
#>
[CmdletBinding()]
param(
    [switch]$Simulation,
    [switch]$Real
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$context = $null

try {
    if ($Simulation -and $Real) { throw 'Les paramètres -Simulation et -Real sont incompatibles.' }

    # Modules importés par chemin absolu (jamais par nom : aucune recherche dans PSModulePath).
    foreach ($module in 'FastPrepare.Core', 'FastPrepare.Infrastructure', 'FastPrepare.Application', 'FastPrepare.UI') {
        Import-Module -Name (Join-Path $PSScriptRoot "src\$module\$module.psd1") -Force
    }

    Assert-Administrator

    $loaded = Read-AppConfig -Path (Join-Path $PSScriptRoot 'config.json')
    $requestedMode = if ($Real) { 'Real' } elseif ($Simulation) { 'Simulation' } else { $null }
    $contextArguments = @{ Root = $PSScriptRoot; Config = $loaded.Config }
    if ($requestedMode) { $contextArguments.RequestedMode = $requestedMode }
    $context = New-AppContext @contextArguments
    foreach ($warning in $loaded.Warnings) {
        Write-RunLog -Log $context.Log -Level ATTN -Message "Configuration : $warning"
    }

    Start-MainWindow -Context $context
} catch {
    $message = $_.Exception.Message
    if ($context) { Write-RunLog -Log $context.Log -Level ERREUR -Message "Arrêt de l'outil : $message" }
    [System.Windows.MessageBox]::Show($message, 'Préparation de poste', 'OK', 'Error') | Out-Null
    exit 1
}
