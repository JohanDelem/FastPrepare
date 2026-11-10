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
    # Racine des profils lue dans le registre au relevé (jamais déduite du chemin à supprimer).
    if (-not $Snapshot.Profiles) {
        New-PlanWarning -Message 'Emplacement des profils inconnu (relevé incomplet) : dossier OneDrive non supprimé.'
        return
    }
    $profilesRoot = [string]$Snapshot.Profiles.Root
    $profilePath = [string]$Snapshot.Profiles.Current
    if (-not (Test-SafeProfilePath -Path $folder.Path -ProfilesRoot $profilesRoot -CurrentProfile $profilePath -AllowInsideProfile)) {
        New-PlanWarning -Message ('Dossier OneDrive refusé par la garde de chemin, non supprimé : {0}' -f $folder.Path)
        return
    }
    New-StepAction -Label ("Dossier OneDrive : Remove-Item '{0}' -Recurse ({1} fichier(s))" -f $folder.Path, $folder.FileCount) -Parameters @{
        Kind = 'RemoveFolder'
        Path = [string]$folder.Path
    }
} -Invoke {
    param($Action, $Context)
    $log = $Context.Log
    switch ($Action.Parameters.Kind) {
        'OneDriveUninstall' {
            $result = Uninstall-OneDrive -Log $log
            if (-not $result.Changed) { Write-RunLog -Log $log -Message 'OneDrive : aucun installateur trouvé, déjà désinstallé' }
        }
        'OneDriveDefaultProfileRun' {
            $result = Remove-DefaultProfileOneDriveRun -DefaultProfilePath (Get-ProfileLocation).Default -Log $log
            if (-not $result.Changed) { Write-RunLog -Log $log -Message 'OneDrive : aucune clé Run dans le profil par défaut' }
        }
        'RemoveFolder' {
            # Garde revérifiée au moment de supprimer, avec les emplacements relus dans le registre.
            $profiles = Get-ProfileLocation
            $result = Remove-GuardedFolder -Path $Action.Parameters.Path -ProfilesRoot $profiles.Root -CurrentProfile $profiles.Current -AllowInsideProfile
            if (-not $result.Changed) { Write-RunLog -Log $log -Message "Dossier OneDrive déjà absent : $($Action.Parameters.Path)" }
        }
        default { throw "action inconnue : $($Action.Parameters.Kind)" }
    }
}
