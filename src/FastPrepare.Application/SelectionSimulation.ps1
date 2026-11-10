<#
    Simulation du bouton Lancer : journalise les actions prévues, dans l'ordre d'exécution du
    cahier des charges, sans rien modifier sur le poste.

    TRANSITOIRE (itération 0) : reprise à l'identique du prototype, mais découplée de l'interface
    (elle ne lit que la Selection, le relevé du poste et le contexte). Elle sera remplacée à
    l'itération 2 par le plan d'exécution unique (ExecutionPlan + ExecutionEngine), qui sert à
    la fois à la simulation et à l'exécution réelle.
#>

function Invoke-SelectionSimulation {
    <# Journalise les actions prévues. Renvoie le nombre d'actions. #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]$Selection,
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)]$Context
    )

    $config = $Context.Config
    $log = $Context.Log
    $count = 0

    Write-RunLog -Log $log -Level SIMU -Message "===== Simulation : actions prévues, dans leur ordre d'exécution ====="
    Write-RunLog -Log $log -Level SIMU -Message '1. Inventaire N/S + MAC : déjà exporté au démarrage'

    foreach ($account in @($Selection.LocalAccounts.Items)) {
        Write-RunLog -Log $log -Level SIMU -Message ("2. Session locale : Remove-LocalUser '{0}' + suppression du profil {1}" -f $account.Name, $account.ProfilePath); $count++
    }

    $ms = $Selection.MicrosoftApps
    if ($ms.OfficeClickToRun) { Write-RunLog -Log $log -Level SIMU -Message '3. Office Click-to-Run : ODT /configure avec <Remove All="TRUE"/>'; $count++ }
    if ($ms.OfficeMsi) { Write-RunLog -Log $log -Level SIMU -Message '3. Office MSI 2010-2016 : ODT /configure avec <RemoveMSI/>'; $count++ }
    if ($ms.OutlookClassic) { Write-RunLog -Log $log -Level SIMU -Message '3. Outlook classique : retiré avec la suite Office'; $count++ }
    if ($ms.OutlookNew) { Write-RunLog -Log $log -Level SIMU -Message '3. Nouvel Outlook : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (Microsoft.OutlookForWindows)'; $count++ }
    if ($ms.OneNote) { Write-RunLog -Log $log -Level SIMU -Message '3. OneNote : C2R + Appx Microsoft.Office.OneNote'; $count++ }
    if ($ms.Teams) { Write-RunLog -Log $log -Level SIMU -Message '3. Teams : MSI Teams Machine-Wide Installer + dossier local + Appx MSTeams + Appx MicrosoftTeams'; $count++ }

    if ($ms.OneDrive) {
        Write-RunLog -Log $log -Level SIMU -Message '4. OneDrive : OneDriveSetup.exe /uninstall + clé Run du profil Default'; $count++
        if ($ms.OneDriveFolder) { Write-RunLog -Log $log -Level SIMU -Message ("4. Dossier OneDrive : Remove-Item '{0}' -Recurse" -f $Snapshot.OneDrive.Path); $count++ }
    }

    foreach ($app in (Get-UninstallOrder -Software @($Selection.Software.Items))) {
        if ($app.Silent) {
            Write-RunLog -Log $log -Level SIMU -Message ('5. Désinstallation silencieuse ({0}) : {1} → {2}' -f $app.Method, $app.Name, $app.Command)
        } else {
            Write-RunLog -Log $log -Level ATTN -Message ('5. Désinstallation avec assistant : {0} → {1}' -f $app.Name, $app.Command)
        }
        $count++
    }

    $utilKey = $Selection.VendorUtility.Key
    $util = $null
    if ($utilKey) {
        $util = $config.Utilities.$utilKey
        if ($util.PSObject.Properties['DotNet'] -and @($util.DotNet).Count -gt 0) {
            Write-RunLog -Log $log -Level SIMU -Message ('6. Dépendance : runtime .NET Desktop adapté à la version de {0} proposée par winget' -f $util.Tool); $count++
        }
        foreach ($item in @($util.Install)) {
            if ($item.Type -eq 'winget') {
                Write-RunLog -Log $log -Level SIMU -Message ('6. Utilitaire : winget install --id {0} --source {1} --silent' -f $item.Id, $item.Source)
            } else {
                $url = if ($item.Url) { $item.Url } else { 'lien à renseigner dans config.json' }
                Write-RunLog -Log $log -Level SIMU -Message ('6. Utilitaire : téléchargement direct de {0} ({1})' -f $item.FileName, $url)
            }
            $count++
        }
    }

    if ($Selection.Office.EditionKey) {
        $edition = Get-OfficeEdition -OfficeConfig $config.Office -Key $Selection.Office.EditionKey
        $productId = Get-OfficeProductId -Edition $edition -WithoutTeams:([bool]$Selection.Office.WithoutTeams)
        $excluded = Get-ExcludedOfficeApp -OptionalApp @($config.Office.OptionalApps) -IncludedId @($Selection.Office.IncludedApps)
        $xml = New-OdtInstallXml -ProductId $productId -Channel $edition.Channel -ExcludedApp $excluded -Architecture $config.Office.Architecture -Language $config.Office.Language
        Write-RunLog -Log $log -Level SIMU -Message ('7. Office : {0} via ODT dans {1}, configuration.xml :' -f $edition.Name, $config.Office.OdtFolder); $count++
        foreach ($line in ($xml -split "`r`n")) { Write-RunLog -Log $log -Level SIMU -Message "     $line" }
    }

    foreach ($software in @($config.Software)) {
        if (@($Selection.ExtraSoftware.Ids) -contains $software.Id) {
            $override = if ($software.PSObject.Properties['Override'] -and $software.Override) { " --override `"$($software.Override)`"" } else { '' }
            Write-RunLog -Log $log -Level SIMU -Message ('8. {0} : winget install --id {1} --source {2} --silent{3}' -f $software.Label, $software.WingetId, $software.Source, $override); $count++
        }
    }

    foreach ($adapter in @($Selection.SystemSettings.Ipv6Adapters)) {
        Write-RunLog -Log $log -Level SIMU -Message ("9. IPv6 : Disable-NetAdapterBinding -Name '{0}' -ComponentID ms_tcpip6" -f $adapter.Name); $count++
    }

    if ($Selection.SystemSettings.Power) {
        $m = $config.Power.MonitorTimeoutMinutes
        $s = $config.Power.StandbyTimeoutMinutes
        $parts = @("monitor-timeout-ac $m", "standby-timeout-ac $s")
        if ($config.Power.ApplyOnBattery) { $parts = @("monitor-timeout-ac $m", "monitor-timeout-dc $m", "standby-timeout-ac $s", "standby-timeout-dc $s") }
        Write-RunLog -Log $log -Level SIMU -Message ('10. Alimentation : powercfg /change {0}' -f ($parts -join ', ')); $count++
    }

    if ($util -and $Selection.Updates.VendorUtility) {
        Write-RunLog -Log $log -Level SIMU -Message ('11. MàJ utilitaire : {0} {1}' -f $util.Update.FilePath, $util.Update.Arguments); $count++
    }
    if ($Selection.Updates.WindowsUpdate) {
        Write-RunLog -Log $log -Level SIMU -Message '12. Windows Update : recherche, téléchargement et installation (API Microsoft.Update.Session)'; $count++
    }
    if ($Selection.HostName.Enabled) {
        Write-RunLog -Log $log -Level SIMU -Message ("13. Nom d'hôte : Rename-Computer -NewName '{0}' (pris en compte au redémarrage)" -f $Selection.HostName.Name); $count++
    }

    Write-RunLog -Log $log -Level OK -Message ('14. Simulation terminée : {0} action(s) prévue(s), aucune modification du poste.' -f $count)
    Write-RunLog -Log $log -Level ATTN -Message ('Rappel, à faire à la main : {0}' -f (@($config.ManualReminders) -join ' · '))
    return $count
}
