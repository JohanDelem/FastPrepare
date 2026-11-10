<#
    Création d'une session locale (itération 8) : jamais exécutée pour de vrai sur le poste.
    New-LocalUser, Add-LocalGroupMember, Remove-LocalUser et net.exe sont remplacés par des simulacres.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
    $m = @{ ModuleName = 'FastPrepare.Infrastructure' }
    $newSid = 'S-1-5-21-1111111111-2222222222-3333333333-1005'

    function New-TestSecret([string]$Text) {
        $secret = New-Object System.Security.SecureString
        foreach ($char in $Text.ToCharArray()) { $secret.AppendChar($char) }
        return $secret
    }
}

Describe 'New-LocalAccount' {
    BeforeEach {
        Mock @m Get-LocalUser { throw 'introuvable' }
        Mock @m New-LocalUser { [pscustomobject]@{ Name = $Name; SID = [pscustomobject]@{ Value = $newSid } } }
        Mock @m Add-LocalGroupMember { }
        Mock @m Remove-LocalUser { }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
        $password = New-TestSecret 'Fictif-2026!'
    }

    It 'crée le compte avec le mot de passe en SecureString et l''ajoute aux groupes par SID' {
        $result = New-LocalAccount -Name 'jdupont' -FullName 'Jean Dupont' -Password $password -GroupSid @('S-1-5-32-545', 'S-1-5-32-544') -PasswordNeverExpires
        $result.Sid | Should -Be $newSid
        Should -Invoke @m New-LocalUser -Times 1 -ParameterFilter {
            $Name -eq 'jdupont' -and $FullName -eq 'Jean Dupont' -and $Password -is [System.Security.SecureString] -and $PasswordNeverExpires -and $AccountNeverExpires
        }
        Should -Invoke @m Add-LocalGroupMember -Times 1 -ParameterFilter { [string]$SID -eq 'S-1-5-32-545' -and [string]$Member[0] -eq $newSid }
        Should -Invoke @m Add-LocalGroupMember -Times 1 -ParameterFilter { [string]$SID -eq 'S-1-5-32-544' }
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }

    It 'sans nom complet : le paramètre n''est pas transmis' {
        [void](New-LocalAccount -Name 'jdupont' -Password $password -GroupSid @('S-1-5-32-545'))
        Should -Invoke @m New-LocalUser -Times 1 -ParameterFilter { -not $PSBoundParameters.ContainsKey('FullName') -and -not $PasswordNeverExpires }
    }

    It '« à changer à la première ouverture » : net.exe, avec le nom seul sur la ligne de commande' {
        [void](New-LocalAccount -Name 'jdupont' -Password $password -GroupSid @('S-1-5-32-545') -MustChangePassword)
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter {
            $FilePath -like '*\net.exe' -and $ArgumentList -eq 'user "jdupont" /logonpasswordchg:yes'
        }
    }

    It 'compte déjà existant : refus, rien n''est créé ni modifié' {
        Mock @m Get-LocalUser { [pscustomobject]@{ Name = 'jdupont' } }
        { New-LocalAccount -Name 'jdupont' -Password $password -GroupSid @('S-1-5-32-545') } | Should -Throw '*existe déjà*'
        Should -Invoke @m New-LocalUser -Times 0
        Should -Invoke @m Add-LocalGroupMember -Times 0
    }

    It 'ajout au groupe impossible : le compte créé est retiré (création atomique)' {
        Mock @m Add-LocalGroupMember { throw 'accès refusé' }
        { New-LocalAccount -Name 'jdupont' -Password $password -GroupSid @('S-1-5-32-545') } | Should -Throw '*compte retiré*accès refusé*'
        Should -Invoke @m Remove-LocalUser -Times 1 -ParameterFilter { [string]$SID -eq $newSid }
    }

    It 'option « à changer » impossible : le compte créé est retiré' {
        Mock @m Invoke-ExternalProcess { throw 'code de sortie 2' }
        { New-LocalAccount -Name 'jdupont' -Password $password -GroupSid @('S-1-5-32-545') -MustChangePassword } | Should -Throw '*compte retiré*'
        Should -Invoke @m Remove-LocalUser -Times 1
    }

    It 'retrait impossible après un échec : le message demande une suppression manuelle' {
        Mock @m Add-LocalGroupMember { throw 'accès refusé' }
        Mock @m Remove-LocalUser { throw 'verrouillé' }
        { New-LocalAccount -Name 'jdupont' -Password $password -GroupSid @('S-1-5-32-545') } | Should -Throw '*NON retiré*à la main*'
    }

    It 'options d''expiration contradictoires : refus avant toute création' {
        { New-LocalAccount -Name 'jdupont' -Password $password -GroupSid @('S-1-5-32-545') -PasswordNeverExpires -MustChangePassword } | Should -Throw '*incompatibles*'
        Should -Invoke @m New-LocalUser -Times 0
    }

    It 'refus de la politique de mots de passe par Windows : l''erreur remonte, rien d''autre n''est fait' {
        Mock @m New-LocalUser { throw 'Le mot de passe ne répond pas aux exigences de la stratégie.' }
        { New-LocalAccount -Name 'jdupont' -Password $password -GroupSid @('S-1-5-32-545') } | Should -Throw '*stratégie*'
        Should -Invoke @m Add-LocalGroupMember -Times 0
        Should -Invoke @m Remove-LocalUser -Times 0
    }
}
