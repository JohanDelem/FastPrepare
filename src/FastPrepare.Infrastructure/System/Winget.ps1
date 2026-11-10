<#
    winget (« Programme d'installation d'application »).
    Itération 0 : détection seulement. Réenregistrement et paquet hors ligne : itération 3.
#>

function Test-Winget {
    <# Vrai si winget.exe est disponible pour le compte courant. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool](Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue)
}
