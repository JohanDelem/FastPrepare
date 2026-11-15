<#
    Section « Mises à jour ».
    « Mettre à jour les pilotes et le BIOS » n'est proposée que si une entrée cochée dans la
    section Installations porte une commande de mise à jour (champ Update du catalogue : outil du
    constructeur du poste) ; elle se coche d'elle-même quand cet outil est coché. L'état de la
    section Installations est lu dans la Selection, pas dans ses contrôles.
#>

Register-UiSection -Id 'updates' -Number 7 -Column Right -XamlFile 'Sections\Updates.xaml' -Initialize {
    param($Section, $Context)
    $Section.State.LastTools = ''
} -Refresh {
    param($Section, $Selection)
    $selected = @($Selection.Catalog.Ids)
    $labels = @(@($script:Context.SoftwareCatalog) | Where-Object { $selected -contains $_.Id -and $_.Update } | ForEach-Object { [string]$_.Update.Label })
    $tools = $labels -join ', '
    $check = $Section.Controls.ChkDrivers
    $check.Visibility = if ($labels.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    if ($tools -ne $Section.State.LastTools) {
        $check.IsChecked = ($labels.Count -gt 0)
        $check.Content = if ($labels.Count -gt 0) { 'Mettre à jour les pilotes et le BIOS ({0})' -f $tools } else { 'Mettre à jour les pilotes et le BIOS' }
        $Section.State.LastTools = $tools
    }
} -GetSelection {
    param($Section, $Selection)
    $c = $Section.Controls
    $Selection.Updates.WindowsUpdate = [bool]$c.ChkWU.IsChecked
    $Selection.Updates.Drivers = ($c.ChkDrivers.Visibility -eq 'Visible') -and [bool]$c.ChkDrivers.IsChecked
}
