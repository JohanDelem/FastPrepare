BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
    $requirements = @((Get-TestConfig).Utilities.dell.DotNet)
}

Describe 'Test-VersionInRange (bornes incluses, borne vide = ouverte)' {
    It '<Version> dans [<Min> ; <Max>] → <Expected>' -ForEach @(
        @{ Version = '8.0.8'; Min = '8.0.8'; Max = '8.0.25'; Expected = $true }
        @{ Version = '8.0.9'; Min = '8.0.8'; Max = '8.0.25'; Expected = $true }
        @{ Version = '8.0.25'; Min = '8.0.8'; Max = '8.0.25'; Expected = $true }
        @{ Version = '8.0.25.1'; Min = '8.0.8'; Max = '8.0.25'; Expected = $true }
        @{ Version = '8.0.26'; Min = '8.0.8'; Max = '8.0.25'; Expected = $false }
        @{ Version = '8.0.7'; Min = '8.0.8'; Max = '8.0.25'; Expected = $false }
        @{ Version = '10.0.12'; Min = '10.0.8'; Max = ''; Expected = $true }
        @{ Version = '10.0.7'; Min = '10.0.8'; Max = ''; Expected = $false }
    ) {
        Test-VersionInRange -Version $Version -MinVersion $Min -MaxVersion $Max | Should -Be $Expected
    }
    It 'version invalide : erreur' {
        { Test-VersionInRange -Version 'abc' -MinVersion '1.0' -MaxVersion '' } | Should -Throw
    }
}

Describe 'Select-DotNetRequirement (cahier, « Dell et .NET »)' {
    It 'DCU 5.7.0 → .NET 8, plage 8.0.8 à 8.0.25' {
        $result = Select-DotNetRequirement -ToolVersion '5.7.0' -Requirement $requirements
        $result.IsExactMatch | Should -BeTrue
        $result.Requirement.WingetId | Should -Be 'Microsoft.DotNet.DesktopRuntime.8'
        $result.Requirement.MaxVersion | Should -Be '8.0.25'
    }
    It 'DCU 5.7.1 → .NET 10, 10.0.8 ou plus' {
        $result = Select-DotNetRequirement -ToolVersion '5.7.1' -Requirement $requirements
        $result.Requirement.WingetId | Should -Be 'Microsoft.DotNet.DesktopRuntime.10'
    }
    It 'une révision de build (5.7.0.1234) correspond à 5.7.0' {
        (Select-DotNetRequirement -ToolVersion '5.7.0.1234' -Requirement $requirements).IsExactMatch | Should -BeTrue
    }
    It 'version inconnue plus récente : entrée la plus proche en dessous, signalée comme approchée' {
        $result = Select-DotNetRequirement -ToolVersion '5.8.0' -Requirement $requirements
        $result.IsExactMatch | Should -BeFalse
        $result.Requirement.DcuVersion | Should -Be '5.7.1'
    }
    It 'version plus ancienne que toutes les entrées : aucune' {
        Select-DotNetRequirement -ToolVersion '5.6.0' -Requirement $requirements | Should -BeNullOrEmpty
    }
    It 'liste vide : aucune' {
        Select-DotNetRequirement -ToolVersion '5.7.0' -Requirement @() | Should -BeNullOrEmpty
    }
}
