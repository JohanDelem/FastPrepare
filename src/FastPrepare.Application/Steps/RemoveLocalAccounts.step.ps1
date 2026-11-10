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
}
