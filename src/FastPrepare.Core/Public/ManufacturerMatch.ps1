<#
    Présélection de la card constructeur (cahier des charges, section 5). Fonction pure :
    les motifs viennent de config.Utilities.<clé>.ManufacturerPattern.
#>

function Resolve-UtilityKey {
    <# Première clé de config.Utilities dont le motif reconnaît le constructeur ; $null sinon. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Manufacturer,
        [Parameter(Mandatory)]$Utilities
    )
    if ([string]::IsNullOrWhiteSpace($Manufacturer)) { return $null }
    foreach ($property in $Utilities.PSObject.Properties) {
        $pattern = [string]$property.Value.ManufacturerPattern
        if ($pattern -and ($Manufacturer -match $pattern)) { return [string]$property.Name }
    }
    return $null
}
