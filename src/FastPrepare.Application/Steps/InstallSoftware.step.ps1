<#
    Étape 8 — Logiciels du catalogue config.Software (section 8), installés par winget.
#>

Register-Step -Id 'install-software' -Section 8 -Title 'Installation de logiciels' -Plan {
    param($Selection, $Snapshot, $Context)
    $selected = @($Selection.ExtraSoftware.Ids)
    foreach ($software in @($Context.Config.Software)) {
        if ($selected -notcontains $software.Id) { continue }
        $override = if ($software.PSObject.Properties['Override'] -and $software.Override) { " --override `"$($software.Override)`"" } else { '' }
        New-StepAction -Label ('{0} : winget install --id {1} --source {2} --silent{3}' -f $software.Label, $software.WingetId, $software.Source, $override) -Parameters @{
            Kind = 'WingetInstall'; SoftwareId = [string]$software.Id
        }
    }
}
