<#
    Étape 6 — Dépendances (.NET) puis utilitaire constructeur (section 5).
    La version de l'outil proposée par winget n'est connue qu'à l'exécution : la dépendance .NET
    est choisie à ce moment par Select-DotNetRequirement (FastPrepare.Core).
#>

Register-Step -Id 'install-vendor-utility' -Section 5 -Title 'Installation de l''utilitaire constructeur' -Plan {
    param($Selection, $Snapshot, $Context)
    $key = $Selection.VendorUtility.Key
    if (-not $key) { return }
    $utility = $Context.Config.Utilities.$key

    if ($utility.PSObject.Properties['DotNet'] -and @($utility.DotNet).Count -gt 0) {
        New-StepAction -Label ('Dépendance : runtime .NET Desktop adapté à la version de {0} proposée par winget' -f $utility.Tool) -Parameters @{
            Kind = 'DotNetDependency'; UtilityKey = $key
        }
    }

    $index = 0
    foreach ($item in @($utility.Install)) {
        if ($item.Type -eq 'winget') {
            $label = 'Utilitaire : winget install --id {0} --source {1} --silent' -f $item.Id, $item.Source
        } else {
            $url = if ($item.Url) { $item.Url } else { 'lien à renseigner dans config.json' }
            $label = 'Utilitaire : téléchargement direct de {0} ({1})' -f $item.FileName, $url
            if (-not $item.Url) { New-PlanWarning -Message ("{0} : lien de téléchargement de {1} vide dans config.json, l'installation réelle échouera." -f $utility.Tool, $item.FileName) }
        }
        New-StepAction -Label $label -Parameters @{ Kind = 'UtilityInstall'; UtilityKey = $key; ItemIndex = $index }
        $index++
    }
}
