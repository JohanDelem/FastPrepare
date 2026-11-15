<#
    Étape 6 — Installations : entrées cochées du catalogue (outil du constructeur compris), dans
    l'ordre du catalogue, puis Office, l'installation la plus longue (DEC26).
    L'étape ne fait qu'assembler : le catalogue est installé par Install\CatalogInstall.ps1,
    Office par Install\OfficeInstall.ps1.
#>

Register-Step -Id 'install' -Title 'Installations' -Plan {
    param($Selection, $Snapshot, $Context)
    Get-CatalogInstallAction -Selection $Selection -Context $Context
    Get-OfficeInstallAction -Selection $Selection -Context $Context
} -Invoke {
    param($Action, $Context)
    switch ($Action.Parameters.Kind) {
        'DotNetDependency' { Invoke-CatalogDotNetDependency -Software $Action.Parameters.Software -Context $Context }
        'CatalogInstall' { Invoke-CatalogInstall -Software $Action.Parameters.Software -Context $Context }
        'OdtInstall' { Invoke-OfficeInstall -Action $Action -Context $Context }
        default { throw "action inconnue : $($Action.Parameters.Kind)" }
    }
}
