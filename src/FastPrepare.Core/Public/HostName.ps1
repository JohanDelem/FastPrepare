<#
    Règle du nom d'hôte (cahier des charges, section 1).
    15 caractères maximum, lettres ASCII, chiffres et tiret, pas de tiret en début ni en fin,
    pas uniquement des chiffres. Fonctions pures.
#>

function Get-HostNameError {
    <# Renvoie le motif lisible du refus, ou $null si le nom est valide. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Name
    )
    if ([string]::IsNullOrEmpty($Name)) { return 'nom vide' }
    if ($Name.Length -gt 15) { return ('{0} caractères sur 15 maximum' -f $Name.Length) }
    if ($Name -cnotmatch '^[A-Za-z0-9-]+$') { return 'caractères autorisés : lettres sans accent, chiffres, tiret' }
    if ($Name.StartsWith('-') -or $Name.EndsWith('-')) { return 'pas de tiret en début ni en fin' }
    if ($Name -match '^\d+$') { return 'ne peut pas être composé uniquement de chiffres' }
    return $null
}

function Test-HostName {
    <# Vrai si le nom d'hôte respecte la règle. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Name
    )
    return ($null -eq (Get-HostNameError -Name $Name))
}
