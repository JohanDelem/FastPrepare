BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
    $prefix = 'S-1-5-21-1111111111-2222222222-3333333333'
    $current = "$prefix-1001"
}

Describe 'Test-ProtectedAccount (cahier, section 4)' {
    It 'RID <Rid> protégé' -ForEach @(@{ Rid = 500 }, @{ Rid = 501 }, @{ Rid = 503 }, @{ Rid = 504 }) {
        Test-ProtectedAccount -Sid "$prefix-$Rid" -CurrentSid $current | Should -BeTrue
    }
    It 'compte connecté protégé' {
        Test-ProtectedAccount -Sid $current -CurrentSid $current | Should -BeTrue
    }
    It 'autre compte supprimable' {
        Test-ProtectedAccount -Sid "$prefix-1002" -CurrentSid $current | Should -BeFalse
    }
    It 'un RID qui se termine par 500 n''est pas confondu (ex. 1500)' {
        Test-ProtectedAccount -Sid "$prefix-1500" -CurrentSid $current | Should -BeFalse
    }
}

Describe 'Split-LocalAccount' {
    It 'sépare supprimables et exclus, avec le motif du compte connecté' {
        $accounts = @(
            [pscustomobject]@{ Name = 'Administrateur'; Sid = "$prefix-500" }
            [pscustomobject]@{ Name = 'technicien'; Sid = $current }
            [pscustomobject]@{ Name = 'ancien'; Sid = "$prefix-1002" }
        )
        $result = Split-LocalAccount -Account $accounts -CurrentSid $current
        @($result.Removable).Name | Should -Be @('ancien')
        $result.Excluded | Should -Be @('Administrateur', 'technicien (connecté)')
        $result.Names | Should -Be @('Administrateur', 'technicien', 'ancien')
    }
}
