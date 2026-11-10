<#
    Section 4 — Suppression des sessions locales.
    Les comptes protégés sont écartés par FastPrepare.Core (Split-LocalAccount) et listés à part.
#>

Register-UiSection -Id 'local-accounts' -Number 4 -Column Left -XamlFile 'Sections\LocalAccounts.xaml' -Initialize {
    param($Section, $Context)
    $Section.State.Checks = New-Object System.Collections.Generic.List[object]
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $c = $Section.Controls
    $c.PnlUsers.Children.Clear()
    $Section.State.Checks.Clear()
    foreach ($account in @($Snapshot.LocalAccounts.Removable)) {
        $profileText = if ($account.ProfilePath) { "compte + profil $($account.ProfilePath)" } else { 'compte (aucun profil sur le disque)' }
        $check = New-CheckItem -Content ('{0} — {1}' -f $account.Name, $profileText) -Tag $account
        [void]$c.PnlUsers.Children.Add($check)
        $Section.State.Checks.Add($check)
    }
    $c.TxtUsersNone.Visibility = if ($Section.State.Checks.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    $c.TxtUsersExcluded.Text = "Exclus d'office : " + (@($Snapshot.LocalAccounts.Excluded) -join ' · ')
} -GetSelection {
    param($Section, $Selection)
    $Selection.LocalAccounts.Items = @($Section.State.Checks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
}
