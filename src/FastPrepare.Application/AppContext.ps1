<#
    Contexte d'une exécution : configuration, chemins, mode, journal.
    Remplace les variables $script: globales du prototype ; il est passé explicitement
    à chaque fonction qui en a besoin et ne contient aucun objet WPF.
#>

# Mode réel disponible depuis l'itération 3 ; les étapes pas encore implémentées en réel sont
# ignorées (et signalées) par le moteur, jamais exécutées à moitié.
$script:RealModeAvailable = $true

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

    $variables = Get-ConfigPathVariable -Config $Config
    $log = New-RunLog -Folder $logFolder -FallbackFolder (Join-Path $env:TEMP 'FastPrepare') -HostName $env:COMPUTERNAME -Stamp $stamp

    $catalogPath = [string]$Config.SoftwareCatalog
    if (-not [System.IO.Path]::IsPathRooted($catalogPath)) { $catalogPath = Join-Path $Root $catalogPath }

    $context = [pscustomobject]@{
        PSTypeName = 'FastPrepare.AppContext'
        Root       = $Root
        Config     = $Config
        # Catalogue de la section 8 (software.json) ; remplacé quand l'onglet Réglages enregistre.
        SoftwareCatalog = @()
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
            # Paquet winget hors ligne, relatif à la racine de la clé.
            WingetBundle = Join-Path $Root ([string]$Config.Winget.OfflineBundle)
            # Cache des téléchargements (préchargement des utilitaires constructeurs).
            Cache        = $variables['CacheFolder']
            # Variables acceptées dans les chemins de config.json (%ProgramFiles%…).
            Variables    = $variables
            SoftwareCatalog = $catalogPath
        }
    }

    Write-RunLog -Log $log -Message "Journal : $($log.FilePath)"
    if ($log.IsFallback) {
        Write-RunLog -Log $log -Level ATTN -Message "Dossier $logFolder non accessible en écriture : journal et inventaire écrits dans $($log.Folder)"
    }
    Write-RunLog -Log $log -Message ("Mode : {0}" -f $(if ($mode -eq 'Simulation') { 'simulation (aucune modification du poste)' } else { 'réel' }))

    # Un catalogue invalide est refusé au démarrage, comme config.json.
    $catalog = Read-SoftwareCatalog -Path $catalogPath
    $context.SoftwareCatalog = @($catalog.Entries)
    foreach ($warning in @($catalog.Warnings)) { Write-RunLog -Log $log -Level ATTN -Message $warning }
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

function Get-ConfigPathVariable {
    <#
        Table des variables autorisées dans les chemins de config.json (Expand-ConfigPath) :
        ProgramFiles, ProgramFiles(x86), ProgramData, OdtFolder, CacheFolder.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)]$Config)
    $variables = @{
        'ProgramFiles'      = [Environment]::GetFolderPath('ProgramFiles')
        'ProgramFiles(x86)' = [Environment]::GetFolderPath('ProgramFilesX86')
        'ProgramData'       = [Environment]::GetFolderPath('CommonApplicationData')
        'OdtFolder'         = [string]$Config.Office.OdtFolder
    }
    $variables['CacheFolder'] = Expand-ConfigPath -Path ([string]$Config.Execution.CacheFolder) -Variables $variables
    return $variables
}
