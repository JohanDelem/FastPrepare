<#
    Section 8 — Installation de logiciels.
    Cases générées depuis config.Software : ajouter un logiciel = une entrée dans config.json.
#>

Register-UiSection -Id 'software' -Number 8 -Column Right -XamlFile 'Sections\Software.xaml' -Initialize {
    param($Section, $Context)
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($software in @($Context.Config.Software)) {
        $check = New-CheckItem -Content $software.Label -Tag $software.Id -IsChecked ([bool]$software.DefaultChecked)
        [void]$Section.Controls.PnlSoftware.Children.Add($check)
        $checks.Add($check)
    }
    $Section.State.Checks = $checks.ToArray()
} -GetSelection {
    param($Section, $Selection)
    $Selection.ExtraSoftware.Ids = @($Section.State.Checks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
}
