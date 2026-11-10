<#
    Correspondance version de l'outil constructeur → runtime .NET requis
    (cahier des charges, « Dell et .NET » : un runtime trop récent fait échouer DCU 5.7.0).
    Les plages viennent de config.Utilities.<clé>.DotNet. Fonctions pures.
#>

function ConvertTo-ComparableVersion {
    <# [version] à partir d'un texte ; $null si le texte n'est pas un numéro de version. #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $text = $Value.Trim()
    if ($text -notmatch '\.') { $text = "$text.0" }
    return ($text -as [version])
}

function Test-VersionPrefix {
    <# Vrai si -Version commence par les composants de -Prefix (5.7.0 couvre 5.7.0 et 5.7.0.1234). #>
    param([version]$Version, [version]$Prefix)
    if ($Version.Major -ne $Prefix.Major -or $Version.Minor -ne $Prefix.Minor) { return $false }
    if ($Prefix.Build -ge 0 -and $Version.Build -ne $Prefix.Build) { return $false }
    if ($Prefix.Revision -ge 0 -and $Version.Revision -ne $Prefix.Revision) { return $false }
    return $true
}

function Test-VersionInRange {
    <#
        Vrai si -Version est dans [MinVersion ; MaxVersion], bornes incluses, borne vide = ouverte.
        Comparaison numérique ([version]), jamais textuelle : 8.0.9 < 8.0.25.
        Une borne exprimée sur moins de composants couvre toutes les révisions (8.0.25 inclut 8.0.25.1).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Version,
        [AllowEmptyString()][string]$MinVersion,
        [AllowEmptyString()][string]$MaxVersion
    )

    $v = ConvertTo-ComparableVersion -Value $Version
    if (-not $v) { throw "Numéro de version invalide : '$Version'." }
    $min = ConvertTo-ComparableVersion -Value $MinVersion
    $max = ConvertTo-ComparableVersion -Value $MaxVersion

    if ($min -and $v -lt $min) { return $false }
    if ($max -and $v -gt $max -and -not (Test-VersionPrefix -Version $v -Prefix $max)) { return $false }
    return $true
}

function Select-DotNetRequirement {
    <#
        Entrée de config.Utilities.<clé>.DotNet qui s'applique à la version d'outil -ToolVersion.
        Renvoie { Requirement, IsExactMatch } :
          - IsExactMatch vrai : l'entrée correspond à la version (5.7.0 couvre 5.7.0.xxxx) ;
          - IsExactMatch faux : version inconnue de la configuration, l'entrée de la plus grande
            version inférieure est retenue (l'appelant journalise un avertissement) ;
        $null si aucune entrée ne s'applique (outil plus ancien que toutes les entrées, ou liste vide).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolVersion,
        [AllowEmptyCollection()][object[]]$Requirement
    )

    $tool = ConvertTo-ComparableVersion -Value $ToolVersion
    if (-not $tool) { throw "Numéro de version invalide : '$ToolVersion'." }

    $candidates = @(@($Requirement) | Where-Object { $_ } | ForEach-Object {
            $version = ConvertTo-ComparableVersion -Value ([string]$_.DcuVersion)
            if ($version) { [pscustomobject]@{ Version = $version; Entry = $_ } }
        })

    foreach ($candidate in $candidates) {
        if (Test-VersionPrefix -Version $tool -Prefix $candidate.Version) {
            return [pscustomobject]@{ Requirement = $candidate.Entry; IsExactMatch = $true }
        }
    }

    $lower = @($candidates | Where-Object { $_.Version -lt $tool } | Sort-Object -Property Version -Descending)
    if ($lower.Count -gt 0) {
        return [pscustomobject]@{ Requirement = $lower[0].Entry; IsExactMatch = $false }
    }
    return $null
}
