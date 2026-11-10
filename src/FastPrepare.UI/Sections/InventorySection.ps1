<#
    Section 10 — Numéro de série et adresses MAC.
    Affichage, bouton Copier et emplacement de l'export (fait au démarrage par
    FastPrepare.Application, Export-MachineInventory).
#>

Register-UiSection -Id 'inventory' -Number 10 -Column Right -XamlFile 'Sections\Inventory.xaml' -Initialize {
    param($Section, $Context)
    $Section.Controls.BtnCopy.Add_Click({
            Invoke-UiAction -Name 'copie de l''inventaire' -Action {
                [System.Windows.Clipboard]::SetText((Get-UiSection -Id 'inventory').State.Text)
                Write-RunLog -Log $script:Context.Log -Level OK -Message 'N/S et adresses MAC copiés dans le presse-papiers'
            }
        })
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $Section.State.Text = $Snapshot.InventoryText
    $Section.Controls.TxtInventory.Text = $Snapshot.InventoryText
    $Section.Controls.BtnCopy.IsEnabled = [bool]$Snapshot.InventoryText
    $export = $Snapshot.InventoryExport
    $Section.Controls.TxtExport.Text = if ($export -and $export.Path) { "Exporté dans $($export.Path)" }
    elseif ($export) { "Export impossible : $($export.Error)" }
    else { '' }
}
