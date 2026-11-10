<#
    Emplacements des profils utilisateurs, lus dans le registre au moment de l'exécution :
    la garde de chemin (Test-SafeProfilePath, FastPrepare.Core) ne se fie jamais à une racine
    déduite du chemin à supprimer.
#>

$script:ProfileListKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

function Get-ProfileLocation {
    <# { Root (en général C:\Users), Current (profil du compte qui exécute l'outil), Default (profil par défaut) }. #>
    [CmdletBinding()]
    param()
    $list = Get-ItemProperty -Path $script:ProfileListKey -ErrorAction Stop
    return [pscustomobject]@{
        Root    = [Environment]::ExpandEnvironmentVariables([string]$list.ProfilesDirectory)
        Current = [Environment]::GetFolderPath('UserProfile')
        Default = [Environment]::ExpandEnvironmentVariables([string]$list.Default)
    }
}

function Remove-GuardedFolder {
    <#
        Supprime un dossier récursivement, seulement s'il passe la garde de chemin.
        -AllowInsideProfile : sous-dossier d'un profil (OneDrive, dossier Teams), jamais le profil entier.
        Sans effet si le dossier n'existe pas. Renvoie { Changed }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ProfilesRoot,
        [Parameter(Mandatory)][string]$CurrentProfile,
        [switch]$AllowInsideProfile
    )
    if (-not (Test-SafeProfilePath -Path $Path -ProfilesRoot $ProfilesRoot -CurrentProfile $CurrentProfile -AllowInsideProfile:$AllowInsideProfile)) {
        throw "Suppression refusée par la garde de chemin : $Path"
    }
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ Changed = $false } }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    return [pscustomobject]@{ Changed = $true }
}

function Stop-ProcessByName {
    <# Arrête les processus portant ces noms (sans extension) ; aucun = rien à faire. Renvoie le nombre arrêté. #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][string[]]$Name)
    $processes = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    foreach ($process in $processes) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    return $processes.Count
}
