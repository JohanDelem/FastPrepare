<#
    Règles de saisie d'une session locale à créer (fonctionnalité F1, plan d'architecture §3.3).
    Fonctions pures : les noms existants et le nom du poste sont fournis par l'appelant.
    Le mot de passe reste une SecureString : il n'est jamais converti en chaîne managée (DEC15).
#>

# Caractères refusés par Windows dans un nom de compte local.
$script:ForbiddenAccountNameChars = '"/\[]:;|=,+*?<>@'
$script:MaxAccountNameLength = 20
$script:MaxPasswordLength = 127

# Groupes locaux bien connus, désignés par SID (leur nom dépend de la langue de Windows).
$script:UsersGroupSid = 'S-1-5-32-545'
$script:AdministratorsGroupSid = 'S-1-5-32-544'

function Get-LocalAccountNameError {
    <#
        Motif lisible du refus d'un nom de session à créer, ou $null s'il est acceptable.
        -ExistingName : comptes locaux qui existeront encore au moment de la création ;
        -ComputerName : nom(s) du poste (actuel et futur), qu'un compte ne doit pas porter.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Name,
        [AllowEmptyCollection()][string[]]$ExistingName = @(),
        [AllowEmptyCollection()][string[]]$ComputerName = @()
    )
    if (-not $Name) { return 'nom de session vide' }
    if ($Name.Length -gt $script:MaxAccountNameLength) {
        return ('{0} caractères sur {1} maximum' -f $Name.Length, $script:MaxAccountNameLength)
    }
    foreach ($char in $Name.ToCharArray()) {
        if ($script:ForbiddenAccountNameChars.IndexOf($char) -ge 0) { return ("caractère interdit : {0}" -f $char) }
        if ([char]::IsControl($char)) { return 'caractère de contrôle interdit' }
    }
    if ($Name.Trim(' .').Length -eq 0) { return 'uniquement des points ou des espaces' }
    if ($Name.EndsWith('.')) { return 'ne doit pas se terminer par un point' }
    if ($Name -ne $Name.Trim()) { return 'espace en début ou en fin de nom' }
    foreach ($existing in @($ExistingName)) {
        if ($existing -and [string]::Equals($existing, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return ("la session '{0}' existe déjà sur le poste" -f $existing)
        }
    }
    foreach ($computer in @($ComputerName)) {
        if ($computer -and [string]::Equals($computer, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'identique au nom du poste'
        }
    }
    return $null
}

function Get-LocalAccountPasswordError {
    <#
        Motif lisible du refus d'un mot de passe, ou $null s'il est acceptable.
        Sans -Confirmation, seules la présence et la longueur sont vérifiées.
        La politique du poste (longueur, complexité) est appliquée par Windows à la création.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][System.Security.SecureString]$Password,
        [AllowNull()][System.Security.SecureString]$Confirmation
    )
    if ($null -eq $Password) { return 'mot de passe vide' }
    # Une SecureString déjà libérée a une longueur $null : PowerShell masque l'exception de la propriété.
    $length = $Password.Length
    if ($null -eq $length) { return 'mot de passe indisponible (déjà libéré) : saisissez-le de nouveau' }
    if ($length -eq 0) { return 'mot de passe vide' }
    if ($length -gt $script:MaxPasswordLength) {
        return ('mot de passe de {0} caractères sur {1} maximum' -f $length, $script:MaxPasswordLength)
    }
    if ($PSBoundParameters.ContainsKey('Confirmation')) {
        if (-not (Test-SecureStringEqual -First $Password -Second $Confirmation)) { return 'la confirmation ne correspond pas au mot de passe' }
    }
    return $null
}

function Get-LocalAccountGroupSid {
    <# SID des groupes d'une session créée : Utilisateurs toujours, Administrateurs si demandé. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([switch]$Administrator)
    if ($Administrator) { return @($script:UsersGroupSid, $script:AdministratorsGroupSid) }
    return @($script:UsersGroupSid)
}

function Format-LocalAccountSummary {
    <#
        Description d'une session à créer, pour le journal et la confirmation : nom, nom complet,
        groupe, option d'expiration. Ne reçoit pas le mot de passe, et ne peut donc pas l'écrire.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$FullName,
        [switch]$Administrator,
        [switch]$PasswordNeverExpires,
        [switch]$MustChangePassword
    )
    $text = "'$Name'"
    if ($FullName) { $text += " ($FullName)" }
    $text += if ($Administrator) { ' · administrateur du poste' } else { ' · utilisateur standard' }
    if ($MustChangePassword) { $text += ' · mot de passe à changer à la première ouverture' }
    elseif ($PasswordNeverExpires) { $text += " · mot de passe qui n'expire jamais" }
    return $text
}

function Test-SecureStringEqual {
    <#
        Compare deux SecureString sans créer de chaîne managée : lecture caractère par caractère
        dans des copies non managées, effacées et libérées en toutes circonstances.
    #>
    param(
        [AllowNull()][System.Security.SecureString]$First,
        [AllowNull()][System.Security.SecureString]$Second
    )
    if ($null -eq $First -or $null -eq $Second) { return ($null -eq $First -and $null -eq $Second) }
    $length = $First.Length
    # Longueur $null : SecureString libérée (voir Get-LocalAccountPasswordError).
    if ($null -eq $length -or $null -eq $Second.Length -or $length -ne $Second.Length) { return $false }

    $marshal = [System.Runtime.InteropServices.Marshal]
    $firstPtr = [IntPtr]::Zero
    $secondPtr = [IntPtr]::Zero
    try {
        $firstPtr = $marshal::SecureStringToBSTR($First)
        $secondPtr = $marshal::SecureStringToBSTR($Second)
        $equal = $true
        for ($i = 0; $i -lt $length; $i++) {
            # Pas de sortie anticipée : la durée ne dépend pas de la position de la différence.
            if ($marshal::ReadInt16($firstPtr, $i * 2) -ne $marshal::ReadInt16($secondPtr, $i * 2)) { $equal = $false }
        }
        return $equal
    } finally {
        if ($firstPtr -ne [IntPtr]::Zero) { $marshal::ZeroFreeBSTR($firstPtr) }
        if ($secondPtr -ne [IntPtr]::Zero) { $marshal::ZeroFreeBSTR($secondPtr) }
    }
}
