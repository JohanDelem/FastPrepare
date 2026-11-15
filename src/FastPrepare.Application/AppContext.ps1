<#
    Contexte d'une exécution : configuration, chemins, mode, journal.
    Remplace les variables $script: globales du prototype ; il est passé explicitement
    à chaque fonction qui en a besoin et ne contient aucun objet WPF.
#>

function New-AppContext {
    <#
        Crée le contexte et le journal. -Root : dossier de l'outil, quel que soit son support
        (dossier local, téléchargé, partage réseau, support amovible). -RequestedMode (ligne de
        commande) prime sur config.Execution.DefaultMode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Config,
        [ValidateSet('Simulation', 'Real')][string]$RequestedMode
    )

    $mode = if ($RequestedMode) { $RequestedMode } else { [string]$Config.Execution.DefaultMode }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    # Dossier de sortie (journal, inventaire) : relatif au dossier de l'outil, absolu ou réseau (DEC23).
    $outputFolder = [string]$Config.Output.Folder
    if (-not [System.IO.Path]::IsPathRooted($outputFolder)) { $outputFolder = Join-Path $Root $outputFolder }

    $variables = Get-ConfigPathVariable -Config $Config
    $workFolder = $variables['WorkFolder']
    $log = New-RunLog -Folder $outputFolder -FallbackFolder (Join-Path $workFolder 'sortie') -HostName $env:COMPUTERNAME -Stamp $stamp
    $version = Read-ToolVersion -Path (Join-Path $Root 'VERSION')

    $wingetBundle = ''
    if ($Config.Winget.PSObject.Properties['OfflineBundle'] -and $Config.Winget.OfflineBundle) {
        $wingetBundle = [string]$Config.Winget.OfflineBundle
        if (-not [System.IO.Path]::IsPathRooted($wingetBundle)) { $wingetBundle = Join-Path $Root $wingetBundle }
    }

    $catalogPath = [string]$Config.SoftwareCatalog
    if (-not [System.IO.Path]::IsPathRooted($catalogPath)) { $catalogPath = Join-Path $Root $catalogPath }

    $context = [pscustomobject]@{
        PSTypeName = 'FastPrepare.AppContext'
        Root       = $Root
        Version    = $version
        Config     = $Config
        # Catalogue de la section 8 (software.json) ; remplacé quand l'onglet Réglages enregistre.
        SoftwareCatalog = @()
        Mode       = $mode
        Stamp      = $stamp
        Log        = $log
        # Modules chargés dans les runspaces d'arrière-plan (jamais FastPrepare.UI).
        ModulePaths = @(Get-BackgroundModulePath -Root $Root)
        Paths      = [pscustomobject]@{
            # Dossier de l'outil (lecture seule possible) et dossier réellement utilisé pour la sortie.
            Tool      = $Root
            Output    = $log.Folder
            Logos     = Join-Path $Root 'logos'
            # Dossier de travail local sur le poste : téléchargements et Office Deployment Tool,
            # supprimés en fin d'exécution réussie (DEC28).
            Work      = $workFolder
            Cache     = Join-Path $workFolder 'cache'
            Odt       = Join-Path $workFolder 'odt'
            # Paquet winget hors ligne (facultatif) ; chaîne vide s'il n'est pas configuré.
            WingetBundle = $wingetBundle
            # Variables acceptées dans les chemins de config.json (%ProgramFiles%…).
            Variables    = $variables
            SoftwareCatalog = $catalogPath
        }
    }

    Write-RunLog -Log $log -Message ('FastPrepare {0} — dossier de l''outil : {1}' -f $(if ($version) { $version } else { '(version inconnue)' }), $Root)
    Write-RunLog -Log $log -Message "Journal : $($log.FilePath)"
    if ($log.IsFallback) {
        Write-RunLog -Log $log -Level ATTN -Message "Dossier de sortie $outputFolder non accessible en écriture : journal et inventaire écrits dans $($log.Folder)"
    }
    Write-RunLog -Log $log -Message ("Mode : {0}" -f $(if ($mode -eq 'Simulation') { 'simulation (aucune modification du poste)' } else { 'réel' }))

    # Un catalogue invalide est refusé au démarrage, comme config.json.
    $catalog = Read-SoftwareCatalog -Path $catalogPath
    $context.SoftwareCatalog = @($catalog.Entries)
    foreach ($warning in @($catalog.Warnings)) { Write-RunLog -Log $log -Level ATTN -Message $warning }
    return $context
}

function Get-WingetSourceRepair {
    <#
        Paramètres de la réparation automatique de la source winget (itération 11, DEC21), passés
        explicitement aux fonctions winget (-SourceRepair) : un runspace d'arrière-plan n'hérite
        d'aucun état de module. $null si config.Winget.SourcePackage est absent.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)
    $winget = $Context.Config.Winget
    if (-not $winget.PSObject.Properties['SourcePackage'] -or -not $winget.SourcePackage) { return $null }
    return [pscustomobject]@{
        PackageUrl     = [string]$winget.SourcePackage.Url
        ExpectedSigner = [string]$winget.SourcePackage.ExpectedSigner
        Folder         = Join-Path $Context.Paths.Cache 'winget-source'
    }
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
        ProgramFiles, ProgramFiles(x86), ProgramData, WorkFolder.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)]$Config)
    $variables = @{
        'ProgramFiles'      = [Environment]::GetFolderPath('ProgramFiles')
        'ProgramFiles(x86)' = [Environment]::GetFolderPath('ProgramFilesX86')
        'ProgramData'       = [Environment]::GetFolderPath('CommonApplicationData')
    }
    $variables['WorkFolder'] = Expand-ConfigPath -Path ([string]$Config.Execution.WorkFolder) -Variables $variables
    return $variables
}
