<#
    Étape 2 — Suppression des sessions locales et de leurs profils (section 4).
    Les comptes protégés ne peuvent pas être sélectionnés (Split-LocalAccount, FastPrepare.Core) ;
    Invoke revérifiera Test-ProtectedAccount et Test-SafeProfilePath juste avant de supprimer.
#>

Register-Step -Id 'remove-local-accounts' -Section 4 -Title 'Suppression des sessions locales' -Plan {
    param($Selection, $Snapshot, $Context)
    foreach ($account in @($Selection.LocalAccounts.Items)) {
        $profileText = if ($account.ProfilePath) { "suppression du profil $($account.ProfilePath)" } else { 'aucun profil sur le disque' }
        New-StepAction -Label ("Session locale : Remove-LocalUser '{0}' + {1}" -f $account.Name, $profileText) -Parameters @{
            Kind        = 'RemoveLocalAccount'
            Sid         = [string]$account.Sid
            Name        = [string]$account.Name
            ProfilePath = [string]$account.ProfilePath
        }
    }
} -Invoke {
    param($Action, $Context)
    $p = $Action.Parameters
    # Dernières vérifications juste avant de supprimer, avec l'état relu sur le poste.
    $reason = Get-ProtectedAccountReason -Sid $p.Sid -CurrentSid (Get-CurrentUserSid)
    if ($reason) { throw "compte protégé ($reason), suppression refusée" }
    if ($p.ProfilePath) {
        $profiles = Get-ProfileLocation
        if (-not (Test-SafeProfilePath -Path $p.ProfilePath -ProfilesRoot $profiles.Root -CurrentProfile $profiles.Current)) {
            throw "profil refusé par la garde de chemin : $($p.ProfilePath)"
        }
    }
    $result = Remove-LocalAccountWithProfile -Sid $p.Sid -Log $Context.Log
    if (-not $result.AccountRemoved -and -not $result.ProfileRemoved) {
        Write-RunLog -Log $Context.Log -Message ("Session locale '{0}' déjà absente" -f $p.Name)
    }
}
