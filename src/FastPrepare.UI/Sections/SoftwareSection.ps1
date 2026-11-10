<#
    Section 8 — Installation de logiciels.
    Cases générées depuis le catalogue software.json (Context.SoftwareCatalog), modifiable dans
    l'onglet Réglages ; régénérées quand il change, en conservant les cases cochées.
#>

Register-UiSection -Id 'software' -Number 8 -Column Right -XamlFile 'Sections\Software.xaml' -Initialize {
    param($Section, $Context)
    $Section.State.Checks = @()
    Update-SoftwareCheckList -Section $Section -Context $Context -KeepState:$false
} -OnSettingsChanged {
    param($Section, $Context)
    Update-SoftwareCheckList -Section $Section -Context $Context -KeepState:$true
} -GetSelection {
    param($Section, $Selection)
    $Selection.ExtraSoftware.Ids = @($Section.State.Checks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
}

function Update-SoftwareCheckList {
    <#
        Une case par logiciel du catalogue, info-bulle = commande d'installation. -KeepState : une
        case existante garde son état ; un logiciel nouveau prend sa valeur « coché par défaut ».
    #>
    param($Section, $Context, [switch]$KeepState)
    $previous = @{}
    if ($KeepState) { foreach ($check in @($Section.State.Checks)) { $previous[[string]$check.Tag] = [bool]$check.IsChecked } }

    $panel = $Section.Controls.PnlSoftware
    $panel.Children.Clear()
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($software in @($Context.SoftwareCatalog)) {
        $checked = if ($previous.ContainsKey($software.Id)) { $previous[$software.Id] } else { [bool]$software.DefaultChecked }
        $check = New-CheckItem -Content $software.Label -Tag $software.Id -IsChecked $checked
        $check.ToolTip = Format-SoftwareInstallCommand -Entry $software
        [void]$panel.Children.Add($check)
        $checks.Add($check)
    }
    $Section.State.Checks = $checks.ToArray()
    $Section.Controls.TxtSoftwareNone.Visibility = if ($checks.Count -eq 0) { 'Visible' } else { 'Collapsed' }
}
