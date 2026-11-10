BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
}

Describe 'Test-HostName (cahier, section 1)' {
    It 'accepte <Name>' -ForEach @(
        @{ Name = 'PC-123' }, @{ Name = 'A' }, @{ Name = 'ABCDEFGHIJKLMNO' }, @{ Name = 'poste1' }
    ) {
        Test-HostName -Name $Name | Should -BeTrue
    }

    It 'refuse <Name> (<Why>)' -ForEach @(
        @{ Name = ''; Why = 'vide' }
        @{ Name = 'ABCDEFGHIJKLMNOP'; Why = '16 caractères' }
        @{ Name = '123'; Why = 'uniquement des chiffres' }
        @{ Name = '-PC'; Why = 'tiret initial' }
        @{ Name = 'PC-'; Why = 'tiret final' }
        @{ Name = 'PC_1'; Why = 'souligné' }
        @{ Name = 'PÉ1'; Why = 'accent' }
        @{ Name = 'PC 1'; Why = 'espace' }
    ) {
        Test-HostName -Name $Name | Should -BeFalse
    }
}

Describe 'Get-HostNameError' {
    It 'donne le nombre de caractères quand le nom est trop long' {
        Get-HostNameError -Name 'ABCDEFGHIJKLMNOP' | Should -Be '16 caractères sur 15 maximum'
    }
    It 'signale un nom composé uniquement de chiffres' {
        Get-HostNameError -Name '42' | Should -Match 'chiffres'
    }
    It 'renvoie $null pour un nom valide' {
        Get-HostNameError -Name 'PC-01' | Should -BeNullOrEmpty
    }
}
