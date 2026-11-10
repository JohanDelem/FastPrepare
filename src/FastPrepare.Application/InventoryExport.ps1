<#
    Export de l'inventaire N/S + MAC (cahier des charges, section 10), au démarrage.
    Le fichier est écrit à côté du journal (même dossier, même horodatage).
#>

function Export-MachineInventory {
    <# Écrit Inventaire_<N/S>_<horodatage>.txt. Renvoie { Path, Error } ; ne lève pas d'erreur. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)]$Context
    )

    $fileName = 'Inventaire_{0}_{1}.txt' -f (ConvertTo-SafeFileName -Value $Snapshot.Identity.Serial), $Context.Stamp
    $path = Join-Path $Context.Paths.Logs $fileName
    $content = Format-InventoryExport -Identity $Snapshot.Identity -InventoryText $Snapshot.InventoryText -Date (Get-Date)
    try {
        Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -ErrorAction Stop
        Write-RunLog -Log $Context.Log -Level OK -Message "Inventaire exporté : $path"
        return [pscustomobject]@{ Path = $path; Error = $null }
    } catch {
        Write-RunLog -Log $Context.Log -Level ERREUR -Message "Export de l'inventaire impossible : $($_.Exception.Message)"
        return [pscustomobject]@{ Path = $null; Error = $_.Exception.Message }
    }
}
