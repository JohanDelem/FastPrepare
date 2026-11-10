<#
    Étape 11 — MàJ de l'utilitaire constructeur : pilotes, BIOS (section 7).
#>

Register-Step -Id 'update-vendor-utility' -Section 7 -Title 'Mise à jour par l''utilitaire constructeur' -Plan {
    param($Selection, $Snapshot, $Context)
    $key = $Selection.VendorUtility.Key
    if (-not $key -or -not $Selection.Updates.VendorUtility) { return }
    $update = $Context.Config.Utilities.$key.Update
    New-StepAction -Label ('MàJ utilitaire : {0} {1}' -f $update.FilePath, $update.Arguments) -Parameters @{ Kind = 'UtilityUpdate'; UtilityKey = $key }
}
