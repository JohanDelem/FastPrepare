<#
    Comptes locaux et profils associés. Le choix des comptes supprimables appartient à
    FastPrepare.Core (Split-LocalAccount, Test-ProtectedAccount) ; l'étape revérifie juste avant
    d'appeler Remove-LocalAccountWithProfile.
    Création d'une session (itération 8) : les règles de saisie sont dans FastPrepare.Core
    (LocalAccountCreation.ps1) ; le mot de passe n'est manipulé qu'en SecureString.
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

function New-LocalAccount {
    <#
        Crée une session locale et l'ajoute aux groupes donnés par SID. Atomique : si l'ajout aux
        groupes ou l'option « à changer à la première ouverture » échoue, le compte créé est
        retiré et l'erreur remonte. Un compte existant n'est jamais modifié (DEC16).
        Le profil est créé par Windows à la première ouverture de session. Renvoie { Name, Sid }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$FullName,
        [Parameter(Mandatory)][System.Security.SecureString]$Password,
        [Parameter(Mandatory)][string[]]$GroupSid,
        [switch]$PasswordNeverExpires,
        [switch]$MustChangePassword,
        $Log
    )
    if ($PasswordNeverExpires -and $MustChangePassword) {
        throw "« n'expire jamais » et « à changer à la première ouverture » sont incompatibles."
    }
    if (Test-LocalAccountExist -Name $Name) { throw "la session '$Name' existe déjà : elle n'est pas modifiée." }

    $parameters = @{
        Name                 = $Name
        Password             = $Password
        AccountNeverExpires  = $true
        PasswordNeverExpires = [bool]$PasswordNeverExpires
        ErrorAction          = 'Stop'
    }
    if ($FullName) { $parameters.FullName = $FullName }
    $user = New-LocalUser @parameters
    $sid = [string]$user.SID.Value
    if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Compte local '$Name' créé ($sid)" }

    try {
        foreach ($group in $GroupSid) {
            Add-LocalGroupMember -SID $group -Member $sid -ErrorAction Stop
            if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "'$Name' ajouté au groupe $group" }
        }
        if ($MustChangePassword) {
            # Pas d'équivalent dans New-LocalUser ; la ligne de commande ne contient que le nom.
            $net = Get-SystemExecutablePath -Name 'net.exe'
            [void](Invoke-ExternalProcess -FilePath $net -ArgumentList ('user "{0}" /logonpasswordchg:yes' -f $Name) -TimeoutMinutes 2 -Log $Log)
        }
    } catch {
        $problem = $_.Exception.Message
        try {
            Remove-LocalUser -SID $sid -ErrorAction Stop
            $undo = 'compte retiré'
        } catch {
            $undo = "compte NON retiré, à supprimer à la main : $($_.Exception.Message)"
        }
        throw "configuration de la session '$Name' impossible ($undo) : $problem"
    }
    return [pscustomobject]@{ Name = $Name; Sid = $sid }
}

function Test-LocalAccountExist {
    <# Vrai si un compte local porte ce nom (insensible à la casse, comme Windows). #>
    param([Parameter(Mandatory)][string]$Name)
    $account = $null
    try { $account = Get-LocalUser -Name $Name -ErrorAction Stop } catch { $account = $null }
    return ($null -ne $account)
}
