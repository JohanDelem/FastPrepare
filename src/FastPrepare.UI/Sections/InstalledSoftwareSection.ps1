<#
    Section 2 — Désinstallation des logiciels installés.
    Liste générée depuis le relevé du poste ; « ⚠ Non » = pas de désinstallation silencieuse.
#>

Register-UiSection -Id 'installed-software' -Number 2 -Column Left -XamlFile 'Sections\InstalledSoftware.xaml' -Initialize {
    param($Section, $Context)
    $Section.State.Checks = New-Object System.Collections.Generic.List[object]
    $Section.Controls.ChkAllApps.Add_Click({
            Invoke-UiAction -Name 'tout cocher' -Action {
                $section = Get-UiSection -Id 'installed-software'
                $state = [bool]$section.Controls.ChkAllApps.IsChecked
                foreach ($check in $section.State.Checks) { $check.IsChecked = $state }
            }
        })
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $Section.Controls.PnlApps.Children.Clear()
    $Section.State.Checks.Clear()
    foreach ($software in @($Snapshot.Software)) {
        $row = New-SoftwareRow -Software $software
        [void]$Section.Controls.PnlApps.Children.Add($row.Element)
        $Section.State.Checks.Add($row.CheckBox)
    }
    if (@($Snapshot.Software).Count -eq 0) { $Section.Controls.TxtAppsLoading.Text = 'Aucun logiciel détecté.' }
    else { $Section.Controls.TxtAppsLoading.Visibility = 'Collapsed' }
} -GetSelection {
    param($Section, $Selection)
    $Selection.Software.Items = @($Section.State.Checks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
}
