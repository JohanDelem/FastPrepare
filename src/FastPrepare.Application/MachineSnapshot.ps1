<#
    Relevé du poste : tout ce que la fenêtre affiche, calculé une fois.
    Chaque partie est protégée séparément : un échec de lecture n'empêche pas les autres.
    Exécuté en arrière-plan (Start-MachineSnapshot) : la fenêtre reste réactive pendant les
    requêtes WMI, la lecture du registre et le comptage du dossier OneDrive.
#>

function Start-MachineSnapshot {
    <#
        Lance en arrière-plan le relevé du poste puis l'export de l'inventaire.
        Renvoie le travail (FastPrepare.Infrastructure, Start-BackgroundWork) ; son résultat est
        le relevé, avec InventoryExport renseigné.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    return Start-BackgroundWork -Name 'releve-poste' -ModulePath $Context.ModulePaths -Argument @($Context) -ScriptBlock {
        param($Context)
        $snapshot = Get-MachineSnapshot -Context $Context
        $snapshot.InventoryExport = Export-MachineInventory -Snapshot $snapshot -Context $Context
        $snapshot
    }
}

function Get-MachineSnapshot {
    <#
        Renvoie { Identity, WingetAvailable, Software, LocalAccounts { Removable, Excluded },
        Adapters, OneDrive, SuggestedUtilityKey, InventoryText }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    $log = $Context.Log
    $snapshot = [pscustomobject]@{
        PSTypeName          = 'FastPrepare.MachineSnapshot'
        Identity            = [pscustomobject]@{ Manufacturer = ''; Model = ''; Serial = ''; OsLabel = ''; HostName = $env:COMPUTERNAME }
        WingetAvailable     = $false
        Software            = @()
        LocalAccounts       = [pscustomobject]@{ Removable = @(); Excluded = @() }
        Adapters            = @()
        OneDrive            = [pscustomobject]@{ Path = ''; Exists = $false; FileCount = 0 }
        Profiles            = $null
        SuggestedUtilityKey = $null
        InventoryText       = ''
        InventoryExport     = $null
    }

    Invoke-SnapshotPart -Log $log -Name 'identification du poste' -Action {
        $snapshot.Identity = Get-MachineIdentity
        Write-RunLog -Log $log -Message ('Poste : {0} {1}, N/S {2}' -f $snapshot.Identity.Manufacturer, $snapshot.Identity.Model, $snapshot.Identity.Serial)
    }

    Invoke-SnapshotPart -Log $log -Name 'détection de winget' -Action {
        $snapshot.WingetAvailable = Test-Winget
        if ($snapshot.WingetAvailable) { Write-RunLog -Log $log -Level OK -Message 'Winget détecté' }
        else { Write-RunLog -Log $log -Level ATTN -Message 'Winget introuvable : il sera réenregistré avant les installations' }
    }

    Invoke-SnapshotPart -Log $log -Name 'liste des logiciels' -Action {
        $snapshot.Software = @(Get-InstalledSoftwareView)
        $notSilent = @($snapshot.Software | Where-Object { -not $_.Silent }).Count
        Write-RunLog -Log $log -Message ('{0} logiciels détectés, dont {1} sans désinstallation silencieuse' -f $snapshot.Software.Count, $notSilent)
    }

    Invoke-SnapshotPart -Log $log -Name 'liste des sessions locales' -Action {
        $snapshot.LocalAccounts = Split-LocalAccount -Account @(Get-LocalAccount) -CurrentSid (Get-CurrentUserSid)
    }

    Invoke-SnapshotPart -Log $log -Name 'liste des cartes réseau' -Action {
        $snapshot.Adapters = @(Get-PhysicalAdapter)
    }

    Invoke-SnapshotPart -Log $log -Name 'emplacement des profils' -Action {
        $snapshot.Profiles = Get-ProfileLocation
    }

    Invoke-SnapshotPart -Log $log -Name 'dossier OneDrive' -Action {
        $snapshot.OneDrive = Get-OneDriveFolderInfo -ProfilePath $env:USERPROFILE
    }

    $snapshot.SuggestedUtilityKey = Resolve-UtilityKey -Manufacturer $snapshot.Identity.Manufacturer -Utilities $Context.Config.Utilities
    $snapshot.InventoryText = Format-InventoryText -Serial $snapshot.Identity.Serial -Adapter $snapshot.Adapters
    return $snapshot
}

function Get-InstalledSoftwareView {
    <# Logiciels installés avec leur stratégie de désinstallation, triés par nom. #>
    $items = foreach ($entry in (Get-UninstallEntry)) {
        $target = Get-UninstallProbeTarget -Entry $entry
        $probe = if ($target) { Get-ExecutableProbe -Path $target } else { $null }
        $strategy = Resolve-UninstallStrategy -Entry $entry -ExecutableProbe $probe
        [pscustomobject]@{
            PSTypeName = 'FastPrepare.InstalledSoftware'
            Name       = [string]$entry.DisplayName
            Version    = [string]$entry.DisplayVersion
            Publisher  = [string]$entry.Publisher
            Silent     = $strategy.Silent
            Method     = $strategy.Method
            Command    = $strategy.Command
        }
    }
    return @($items | Sort-Object -Property Name)
}

function Invoke-SnapshotPart {
    param($Log, [string]$Name, [scriptblock]$Action)
    try {
        & $Action
    } catch {
        Write-RunLog -Log $Log -Level ERREUR -Message ("Détection impossible ({0}) : {1}" -f $Name, $_.Exception.Message)
    }
}
