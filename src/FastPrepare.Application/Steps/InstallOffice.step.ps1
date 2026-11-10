<#
    Étape 7 — Office via ODT (section 6).
    XML universel produit par FastPrepare.Core (New-OdtInstallXml) et recopié dans le journal.
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
        Kind = 'OdtInstall'; Xml = $xml; EditionKey = $key
    }
}
