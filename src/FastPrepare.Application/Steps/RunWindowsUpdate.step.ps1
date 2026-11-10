<#
    Étape 12 — Windows Update, une passe complète (section 7). Jamais de redémarrage automatique.
#>

Register-Step -Id 'run-windows-update' -Section 7 -Title 'Windows Update' -Plan {
    param($Selection, $Snapshot, $Context)
    if (-not $Selection.Updates.WindowsUpdate) { return }
    New-StepAction -Label 'Windows Update : recherche, téléchargement et installation (API Microsoft.Update.Session)' -Parameters @{ Kind = 'WindowsUpdate' }
} -Invoke {
    param($Action, $Context)
    $log = $Context.Log
    $pass = Invoke-WindowsUpdatePass -Log $log
    if ($pass.Remaining -gt 0) {
        # Une seule passe (cahier, question QO3) : on signale sans relancer.
        Write-RunLog -Log $log -Level ATTN -Message ('Windows Update : {0} mise(s) à jour encore disponible(s) après cette passe (relancer Windows Update après redémarrage)' -f $pass.Remaining)
    }
    if (@($pass.Failed).Count -gt 0) {
        if ($pass.RebootRequired) { Write-RunLog -Log $log -Level ATTN -Message 'Windows Update : redémarrage nécessaire pour finaliser les mises à jour installées.' }
        throw ('{0} mise(s) à jour en échec sur {1} : {2}' -f @($pass.Failed).Count, $pass.Found, (@($pass.Failed) -join ' ; '))
    }
    Write-RunLog -Log $log -Message ('Windows Update : {0} installée(s) sur {1} trouvée(s)' -f $pass.Installed, $pass.Found)
    [pscustomobject]@{ RebootRequired = $pass.RebootRequired }
}
