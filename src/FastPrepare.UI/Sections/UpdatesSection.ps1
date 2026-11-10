<#
    Section 7 — Mises à jour.
    « MàJ de l'utilitaire constructeur » est grisée si aucune card n'est choisie en section 5 ;
    elle se coche d'elle-même quand une card est choisie. L'état de la section 5 est lu dans la
    Selection, pas dans ses contrôles.
#>

Register-UiSection -Id 'updates' -Number 7 -Column Right -XamlFile 'Sections\Updates.xaml' -Initialize {
    param($Section, $Context)
    $Section.State.LastUtilityKey = $null
} -Refresh {
    param($Section, $Selection)
    $key = $Selection.VendorUtility.Key
    $check = $Section.Controls.ChkUtilUpdate
    $check.IsEnabled = [bool]$key
    if ($key -ne $Section.State.LastUtilityKey) {
        $check.IsChecked = [bool]$key
        $Section.State.LastUtilityKey = $key
    }
} -GetSelection {
    param($Section, $Selection)
    $c = $Section.Controls
    $Selection.Updates.WindowsUpdate = [bool]$c.ChkWU.IsChecked
    $Selection.Updates.VendorUtility = [bool]$c.ChkUtilUpdate.IsEnabled -and [bool]$c.ChkUtilUpdate.IsChecked
}
