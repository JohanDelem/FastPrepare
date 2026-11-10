<#
    Étape 12 — Windows Update, une passe complète (section 7). Jamais de redémarrage automatique.
#>

Register-Step -Id 'run-windows-update' -Section 7 -Title 'Windows Update' -Plan {
    param($Selection, $Snapshot, $Context)
    if (-not $Selection.Updates.WindowsUpdate) { return }
    New-StepAction -Label 'Windows Update : recherche, téléchargement et installation (API Microsoft.Update.Session)' -Parameters @{ Kind = 'WindowsUpdate' }
}
