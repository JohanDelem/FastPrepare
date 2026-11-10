<#
    Droits d'exécution et identité du compte courant.
#>

function Test-Administrator {
    <# Vrai si le processus courant dispose d'un jeton administrateur. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    <# Lève une erreur explicite si l'outil n'est pas lancé en administrateur. #>
    [CmdletBinding()]
    param()
    if (-not (Test-Administrator)) {
        throw "Cet outil doit être lancé en administrateur.`nUtilisez Lancer.cmd."
    }
}

function Get-CurrentUserSid {
    <# SID du compte qui exécute l'outil. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}
