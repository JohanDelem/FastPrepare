<#
    Section 9 — Configuration des paramètres système.
    Désactivation d'IPv6 (une case par carte physique) et mode d'alimentation (durées issues
    de config.Power ; batterie incluse selon Power.ApplyOnBattery).
#>

Register-UiSection -Id 'system-settings' -Number 9 -Column Right -XamlFile 'Sections\SystemSettings.xaml' -Initialize {
    param($Section, $Context)
    $Section.State.NicChecks = New-Object System.Collections.Generic.List[object]
    $power = $Context.Config.Power
    $scope = if ($power.ApplyOnBattery) { 'secteur et batterie' } else { 'secteur' }
    $suffix = if ($power.ApplyOnBattery) { 'ac|dc' } else { 'ac' }
    $Section.Controls.ChkPower.Content = "Éteindre l'écran après {0} min · Mise en veille après {1} min ({2})" -f $power.MonitorTimeoutMinutes, $power.StandbyTimeoutMinutes, $scope
    $Section.Controls.TxtPowerTech.Text = 'powercfg /change monitor-timeout-{0} {1} · standby-timeout-{0} {2}' -f $suffix, $power.MonitorTimeoutMinutes, $power.StandbyTimeoutMinutes
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $Section.Controls.PnlNics.Children.Clear()
    $Section.State.NicChecks.Clear()
    foreach ($nic in @($Snapshot.Adapters)) {
        $suffix = if ($nic.Ipv6Enabled) { '' } else { ' (IPv6 déjà désactivé)' }
        $check = New-CheckItem -Content ('{0} — {1}{2}' -f $nic.Name, $nic.Description, $suffix) -Tag $nic -IsChecked ([bool]$nic.Ipv6Enabled)
        [void]$Section.Controls.PnlNics.Children.Add($check)
        $Section.State.NicChecks.Add($check)
    }
} -GetSelection {
    param($Section, $Selection)
    $Selection.SystemSettings.Ipv6Adapters = @($Section.State.NicChecks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $Selection.SystemSettings.Power = [bool]$Section.Controls.ChkPower.IsChecked
}
