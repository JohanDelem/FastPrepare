<#
    Étape 1 — Relevé et export des N/S et MAC (section 10).
    L'inventaire est exporté au démarrage (décision DEC10) : l'étape ne produit une action que
    si cet export a échoué (clé momentanément inaccessible, par exemple).
#>

Register-Step -Id 'export-inventory' -Section 10 -Title 'Export de l''inventaire N/S + MAC' -Plan {
    param($Selection, $Snapshot, $Context)
    $export = $Snapshot.InventoryExport
    if ($export -and $export.Path) { return }
    New-StepAction -Label 'Inventaire N/S + MAC : nouvel essai d''export (échec au démarrage)' -Parameters @{ Kind = 'ExportInventory' }
}
