<#
    Garde avant toute suppression récursive (profils supprimés en section 4, dossier OneDrive
    en section 3, cache, C:\ODT). Fonctions pures : elles raisonnent sur des chemins absolus,
    sans lire le disque.
#>

# Dossiers de C:\Users qui ne sont jamais des profils supprimables.
$script:ReservedProfileFolders = @('Default', 'Default User', 'Public', 'All Users', 'defaultuser0')

function ConvertTo-NormalizedPath {
    <# Chemin absolu normalisé (résout « .. », supprime le séparateur final) ; erreur si le chemin est relatif. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not [System.IO.Path]::IsPathRooted($Path) -or $Path -notmatch '^[A-Za-z]:\\|^\\\\') {
        throw "Chemin absolu attendu : '$Path'."
    }
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-SafeChildPath {
    <# Vrai si -Path est strictement sous -Root une fois normalisé (pas d'évasion par « .. », pas la racine elle-même). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )
    try {
        $normalizedPath = ConvertTo-NormalizedPath -Path $Path
        $normalizedRoot = ConvertTo-NormalizedPath -Path $Root
    } catch {
        return $false
    }
    return $normalizedPath.StartsWith($normalizedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-SafeProfilePath {
    <#
        Vrai si -Path peut être supprimé récursivement en toute sécurité : strictement sous le
        dossier des profils (-ProfilesRoot, en général C:\Users), sans être un dossier réservé
        (Default, Public…), ni le profil connecté, ni un dossier qui le contient.
        Pour un sous-dossier d'un profil (ex. OneDrive), passer -AllowInsideProfile.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ProfilesRoot,
        [Parameter(Mandatory)][string]$CurrentProfile,
        [switch]$AllowInsideProfile
    )

    if (-not (Test-SafeChildPath -Path $Path -Root $ProfilesRoot)) { return $false }
    $normalizedPath = ConvertTo-NormalizedPath -Path $Path
    $normalizedRoot = ConvertTo-NormalizedPath -Path $ProfilesRoot
    $normalizedCurrent = ConvertTo-NormalizedPath -Path $CurrentProfile

    $relative = $normalizedPath.Substring($normalizedRoot.Length + 1)
    $profileFolder = $relative.Split('\')[0]
    if ($script:ReservedProfileFolders -contains $profileFolder) { return $false }

    $isProfileItself = ($relative.IndexOf('\') -lt 0)
    $insideCurrent = $normalizedPath.Equals($normalizedCurrent, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedCurrent + '\', [System.StringComparison]::OrdinalIgnoreCase)

    if ($AllowInsideProfile) {
        # Sous-dossier d'un profil, y compris celui du compte connecté, mais jamais le profil entier.
        return (-not $isProfileItself)
    }
    # Profil entier d'un autre compte uniquement.
    return ($isProfileItself -and -not $insideCurrent)
}
