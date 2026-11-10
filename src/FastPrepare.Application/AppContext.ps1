<#
    Contexte d'une exécution : configuration, chemins, mode, journal.
    Remplace les variables $script: globales du prototype ; il est passé explicitement
    à chaque fonction qui en a besoin et ne contient aucun objet WPF.
#>

# Le moteur d'exécution réel arrive à l'itération 3 (docs/architecture_plan.md §9).
$script:RealModeAvailable = $false

function New-AppContext {
    <#
        Crée le contexte et le journal. -RequestedMode (ligne de commande) prime sur
        config.Execution.DefaultMode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Config,
        [ValidateSet('Simulation', 'Real')][string]$RequestedMode
    )

    $mode = if ($RequestedMode) { $RequestedMode } else { [string]$Config.Execution.DefaultMode }
    if ($mode -eq 'Real' -and -not $script:RealModeAvailable) {
        throw ("Le mode réel n'est pas encore disponible dans cette version de l'outil.`n" +
            "Lancez l'outil en simulation (Lancer.cmd -Simulation, ou Execution.DefaultMode = 'Simulation' dans config.json).")
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logFolder = [string]$Config.Logging.Folder
    if (-not [System.IO.Path]::IsPathRooted($logFolder)) { $logFolder = Join-Path $Root $logFolder }

    $log = New-RunLog -Folder $logFolder -FallbackFolder (Join-Path $env:TEMP 'FastPrepare') -HostName $env:COMPUTERNAME -Stamp $stamp

    $context = [pscustomobject]@{
        PSTypeName = 'FastPrepare.AppContext'
        Root       = $Root
        Config     = $Config
        Mode       = $mode
        Stamp      = $stamp
        Log        = $log
        # Modules chargés dans les runspaces d'arrière-plan (jamais FastPrepare.UI).
        ModulePaths = @(Get-BackgroundModulePath -Root $Root)
        Paths      = [pscustomobject]@{
            Logs      = $log.Folder
            Logos     = Join-Path $Root 'logos'
            Packages  = Join-Path $Root 'packages'
            OdtFolder = [string]$Config.Office.OdtFolder
        }
    }

    Write-RunLog -Log $log -Message "Journal : $($log.FilePath)"
    if ($log.IsFallback) {
        Write-RunLog -Log $log -Level ATTN -Message "Dossier $logFolder non accessible en écriture : journal et inventaire écrits dans $($log.Folder)"
    }
    Write-RunLog -Log $log -Message ("Mode : {0}" -f $(if ($mode -eq 'Simulation') { 'simulation (aucune modification du poste)' } else { 'réel' }))
    return $context
}

function Get-BackgroundModulePath {
    <# Chemins absolus des manifestes des modules non graphiques, dans l'ordre de dépendance. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Root)
    foreach ($module in 'FastPrepare.Core', 'FastPrepare.Infrastructure', 'FastPrepare.Application') {
        Join-Path $Root "src\$module\$module.psd1"
    }
}
