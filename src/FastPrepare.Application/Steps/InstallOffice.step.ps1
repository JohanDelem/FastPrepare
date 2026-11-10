<#
    Étape 7 — Office via ODT (section 6).
    XML universel produit par FastPrepare.Core (New-OdtInstallXml) et recopié dans le journal.
    Après ODT, le produit est recherché dans la configuration Click-to-Run : un ODT terminé sans
    erreur mais sans produit installé est un échec. Activation manuelle plus tard (cahier).
#>

Register-Step -Id 'install-office' -Section 6 -Title 'Installation d''Office' -Plan {
    param($Selection, $Snapshot, $Context)
    $key = $Selection.Office.EditionKey
    if (-not $key) { return }
    $office = $Context.Config.Office
    $edition = Get-OfficeEdition -OfficeConfig $office -Key $key
    $productId = Get-OfficeProductId -Edition $edition -WithoutTeams:([bool]$Selection.Office.WithoutTeams)
    $excluded = Get-ExcludedOfficeApp -OptionalApp @($office.OptionalApps) -IncludedId @($Selection.Office.IncludedApps)
    $xml = New-OdtInstallXml -ProductId $productId -Channel $edition.Channel -ExcludedApp $excluded -Architecture $office.Architecture -Language $office.Language

    New-StepAction -Label ('Office : {0} via ODT dans {1} (ID produit {2}), configuration.xml :' -f $edition.Name, $office.OdtFolder, $productId) -Details ($xml -split "`r`n") -Parameters @{
        Kind = 'OdtInstall'; Xml = $xml; EditionKey = $key; ProductId = $productId
    }
} -Invoke {
    param($Action, $Context)
    $log = $Context.Log
    $p = $Action.Parameters
    Write-RunLog -Log $log -Message ("Office : téléchargement et installation par ODT, compter plusieurs minutes selon la connexion")
    foreach ($line in ($p.Xml -split "`r`n")) { Write-RunLog -Log $log -Message ('     ' + $line) }
    $setup = Initialize-OdtFolder -Folder $Context.Paths.OdtFolder -SetupUrl $Context.Config.Office.OdtSetupUrl -Log $log
    $result = Invoke-Odt -SetupPath $setup -Xml $p.Xml -Name 'installation' -TimeoutMinutes 120 -Log $log
    $installed = @(Get-OfficeClickToRunProduct)
    if ($installed -notcontains $p.ProductId) {
        $found = if ($installed.Count) { $installed -join ', ' } else { 'aucun' }
        throw ("ODT terminé, mais {0} absent de la configuration Click-to-Run (produits trouvés : {1})" -f $p.ProductId, $found)
    }
    Write-RunLog -Log $log -Message ('Office {0} installé ; activation à faire à la main' -f $p.ProductId)
    [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
