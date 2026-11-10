<#
    Section 1 — Changer le nom d'hôte.
    Champ grisé si la case est décochée ; saisie vérifiée par FastPrepare.Core (Get-HostNameError).
#>

Register-UiSection -Id 'host-name' -Number 1 -Column Left -XamlFile 'Sections\HostName.xaml' -Initialize {
    param($Section, $Context)
    $Section.State.DefaultHint = "15 caractères max · lettres, chiffres, tiret · appliqué au redémarrage"
    $Section.Controls.TxtHostHint.Text = $Section.State.DefaultHint

    $Section.Controls.ChkHost.Add_Click({ Invoke-UiAction -Name "nom d'hôte" -Action { Update-HostNameView; Update-UiState } })
    $Section.Controls.TxtHost.Add_TextChanged({ Invoke-UiAction -Name "nom d'hôte" -Action { Update-HostNameView; Update-UiState } })
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $Section.State.DefaultHint = "Nom actuel : $($Snapshot.Identity.HostName) · 15 caractères max · lettres, chiffres, tiret · appliqué au redémarrage"
    Update-HostNameView
} -GetSelection {
    param($Section, $Selection)
    $Selection.HostName.Enabled = [bool]$Section.Controls.ChkHost.IsChecked
    $Selection.HostName.Name = [string]$Section.Controls.TxtHost.Text
} -Validate {
    param($Section)
    if ($Section.Controls.ChkHost.IsChecked -and -not (Test-HostName -Name $Section.Controls.TxtHost.Text)) {
        return "Grisé : nom d'hôte invalide"
    }
    return $null
}

function Update-HostNameView {
    $section = Get-UiSection -Id 'host-name'
    $controls = $section.Controls
    $enabled = [bool]$controls.ChkHost.IsChecked
    $controls.TxtHost.IsEnabled = $enabled

    $text = [string]$controls.TxtHost.Text
    $problem = if ($enabled -and $text) { Get-HostNameError -Name $text } else { $null }
    if ($problem) {
        $controls.TxtHostHint.Text = 'Nom invalide : {0}' -f $problem
        $controls.TxtHostHint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
    } else {
        $controls.TxtHostHint.Text = $section.State.DefaultHint
        $controls.TxtHostHint.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    }
}
