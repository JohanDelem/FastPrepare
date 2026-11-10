<#
    Comptes locaux et profils associés. Le choix des comptes supprimables appartient à
    FastPrepare.Core (Split-LocalAccount, Test-ProtectedAccount) ; l'étape revérifie juste avant
    d'appeler Remove-LocalAccountWithProfile.
#>

function Get-LocalAccount {
    <# Comptes locaux { Name, Sid, ProfilePath } ; repli sur Win32_UserAccount si Get-LocalUser est indisponible. #>
    [CmdletBinding()]
    param()

    $profiles = @{}
    foreach ($p in (Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue)) {
        $profiles[[string]$p.SID] = [string]$p.LocalPath
    }

    $accounts = $null
    try {
        $accounts = @(Get-LocalUser -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Sid = $_.SID.Value } })
    } catch {
        $accounts = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction SilentlyContinue |
                ForEach-Object { [pscustomobject]@{ Name = $_.Name; Sid = $_.SID } })
    }

    foreach ($account in $accounts) {
        [pscustomobject]@{
            PSTypeName  = 'FastPrepare.LocalAccount'
            Name        = [string]$account.Name
            Sid         = [string]$account.Sid
            ProfilePath = $profiles[[string]$account.Sid]
        }
    }
}

function Remove-LocalAccountWithProfile {
    <#
        Supprime le profil (instance Win32_UserProfile : dossier et clé ProfileList), puis le compte.
        Refuse un profil chargé (session ouverte). Idempotent : compte et profil déjà absents = succès.
        Renvoie { AccountRemoved, ProfileRemoved, LeftoverFolder }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Sid,
        $Log
    )
    if ($Sid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { throw "SID de compte local invalide : '$Sid'." }

    $result = [pscustomobject]@{ AccountRemoved = $false; ProfileRemoved = $false; LeftoverFolder = $null }

    $userProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f $Sid) -ErrorAction SilentlyContinue
    if ($userProfile) {
        if ($userProfile.Loaded) { throw "le profil $($userProfile.LocalPath) est chargé (session ouverte) : fermez la session puis relancez." }
        $folder = [string]$userProfile.LocalPath
        Remove-CimInstance -InputObject $userProfile -ErrorAction Stop
        $result.ProfileRemoved = $true
        if ($folder -and (Test-Path -LiteralPath $folder)) {
            $result.LeftoverFolder = $folder
            if ($Log) { Write-RunLog -Log $Log -Level ATTN -Message "Profil supprimé mais dossier encore présent (fichiers verrouillés ?) : $folder" }
        }
    }

    $account = $null
    try { $account = Get-LocalUser -SID $Sid -ErrorAction Stop } catch { $account = $null }
    if ($account) {
        Remove-LocalUser -SID $Sid -ErrorAction Stop
        $result.AccountRemoved = $true
    }
    return $result
}
