<#
    Étape 4 — OneDrive, puis son dossier (section 3).
    Le dossier n'est proposé à la suppression que s'il passe la garde de chemin (FastPrepare.Core,
    Test-SafeProfilePath -AllowInsideProfile) : jamais le profil entier, jamais Default ou Public.
#>

Register-Step -Id 'remove-onedrive' -Section 3 -Title 'Désinstallation de OneDrive' -Plan {
    param($Selection, $Snapshot, $Context)
    $ms = $Selection.MicrosoftApps
    if (-not $ms.OneDrive) { return }

    New-StepAction -Label 'OneDrive : OneDriveSetup.exe /uninstall (+ /allusers si installé pour tous)' -Parameters @{ Kind = 'OneDriveUninstall' }
    New-StepAction -Label 'OneDrive : retrait de la clé Run OneDriveSetup du profil Default' -Parameters @{ Kind = 'OneDriveDefaultProfileRun' }

    if (-not $ms.OneDriveFolder) { return }
    $folder = $Snapshot.OneDrive
    if (-not $folder.Exists) {
        New-PlanWarning -Message ('Dossier OneDrive absent ({0}) : rien à supprimer.' -f $folder.Path)
        return
    }
    $profilePath = Split-Path -Path $folder.Path -Parent
    $profilesRoot = Split-Path -Path $profilePath -Parent
    if (-not (Test-SafeProfilePath -Path $folder.Path -ProfilesRoot $profilesRoot -CurrentProfile $profilePath -AllowInsideProfile)) {
        New-PlanWarning -Message ('Dossier OneDrive refusé par la garde de chemin, non supprimé : {0}' -f $folder.Path)
        return
    }
    New-StepAction -Label ("Dossier OneDrive : Remove-Item '{0}' -Recurse ({1} fichier(s))" -f $folder.Path, $folder.FileCount) -Parameters @{
        Kind         = 'RemoveFolder'
        Path         = [string]$folder.Path
        ProfilesRoot = [string]$profilesRoot
        Profile      = [string]$profilePath
    }
}
