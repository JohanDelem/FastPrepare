<#
    Format de l'inventaire N/S + adresses MAC (cahier des charges, section 10). Fonctions pures.
#>

function Format-InventoryText {
    <# Bloc aligné affiché dans la fenêtre et copié dans le presse-papiers. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Serial,
        [AllowEmptyCollection()][object[]]$Adapter
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('{0,-22} {1}' -f 'N/S', $Serial))
    foreach ($nic in @($Adapter)) {
        if ($null -eq $nic) { continue }
        $lines.Add(('{0,-22} {1}' -f ('MAC {0}' -f $nic.Name), $nic.Mac))
    }
    return ($lines -join "`r`n")
}

function Format-InventoryExport {
    <# Lignes du fichier d'inventaire exporté. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Identity,
        [AllowEmptyString()][string]$InventoryText,
        [Parameter(Mandatory)][datetime]$Date
    )
    return @(
        ("Date         : {0}" -f $Date.ToString('dd/MM/yyyy HH:mm')),
        ("Nom d'hôte   : {0}" -f $Identity.HostName),
        ("Constructeur : {0}" -f $Identity.Manufacturer),
        ("Modèle       : {0}" -f $Identity.Model),
        $InventoryText
    )
}

function ConvertTo-SafeFileName {
    <# Caractères hors [A-Za-z0-9_-] remplacés par « _ » ; valeur vide → INCONNU. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'INCONNU' }
    return ($Value.Trim() -replace '[^A-Za-z0-9_-]', '_')
}
