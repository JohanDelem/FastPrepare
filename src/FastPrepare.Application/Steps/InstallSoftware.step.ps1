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
} -Invoke {
    param($Action, $Context)
    $software = @($Context.Config.Software) | Where-Object { $_.Id -eq $Action.Parameters.SoftwareId } | Select-Object -First 1
    if (-not $software) { throw "logiciel '$($Action.Parameters.SoftwareId)' absent de config.json" }
    Assert-WingetAvailable -FamilyName $Context.Config.Winget.FamilyName -OfflineBundle $Context.Paths.WingetBundle -Log $Context.Log
    $override = if ($software.PSObject.Properties['Override']) { [string]$software.Override } else { '' }
    $result = Install-WingetPackage -Id $software.WingetId -Source $software.Source -Override $override -Log $Context.Log
    if ($result.AlreadyInstalled) { Write-RunLog -Log $Context.Log -Message ('{0} : déjà installé' -f $software.Label) }
    [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
