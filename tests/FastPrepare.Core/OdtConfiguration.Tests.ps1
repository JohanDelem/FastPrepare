BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
    $office = (Get-TestConfig).Office
}

Describe 'Get-OfficeProductId (licences avec / sans Teams)' {
    It '365 avec Teams : O365BusinessRetail' {
        Get-OfficeProductId -Edition (Get-OfficeEdition -OfficeConfig $office -Key 'O365') | Should -Be 'O365BusinessRetail'
    }
    It '365 sans Teams : O365BusinessEEANoTeamsRetail' {
        Get-OfficeProductId -Edition (Get-OfficeEdition -OfficeConfig $office -Key 'O365') -WithoutTeams | Should -Be 'O365BusinessEEANoTeamsRetail'
    }
    It 'refuse « sans Teams » pour une édition qui ne le propose pas' {
        { Get-OfficeProductId -Edition (Get-OfficeEdition -OfficeConfig $office -Key 'LTSC2024') -WithoutTeams } | Should -Throw
    }
    It 'édition inconnue : erreur' {
        { Get-OfficeEdition -OfficeConfig $office -Key 'INCONNUE' } | Should -Throw
    }
}

Describe 'Get-ExcludedOfficeApp' {
    It 'une ExcludeApp par case décochée, dans l''ordre de la configuration' {
        Get-ExcludedOfficeApp -OptionalApp $office.OptionalApps -IncludedId @('Outlook') | Should -Be @('OutlookForWindows', 'OneDrive')
    }
    It 'toutes cochées : aucune exclusion' {
        @(Get-ExcludedOfficeApp -OptionalApp $office.OptionalApps -IncludedId @('OutlookForWindows', 'Outlook', 'OneDrive')).Count | Should -Be 0
    }
}

Describe 'New-OdtInstallXml (XML universel du cahier)' {
    It 'XML valide pour chaque édition, sans Teams, clé ni organisation' -ForEach @(
        @{ Key = 'O365' }, @{ Key = 'LTSC2024' }, @{ Key = 'STD2019' }, @{ Key = 'PP2019' }
    ) {
        $edition = Get-OfficeEdition -OfficeConfig $office -Key $Key
        $text = New-OdtInstallXml -ProductId $edition.ProductId -Channel $edition.Channel -ExcludedApp @('OneDrive')
        $xml = [xml]$text
        $xml.Configuration.Add.OfficeClientEdition | Should -Be '64'
        $xml.Configuration.Add.Channel | Should -Be $edition.Channel
        $xml.Configuration.Add.Product.ID | Should -Be $edition.ProductId
        $xml.Configuration.Add.Product.Language.ID | Should -Be 'MatchOS'
        $xml.Configuration.Add.Product.ExcludeApp.ID | Should -Be 'OneDrive'
        $xml.Configuration.Display.AcceptEULA | Should -Be 'TRUE'
        $text | Should -Not -Match 'Teams|PIDKEY|CompanyName'
    }
    It 'échappe les caractères spéciaux (construit par System.Xml)' {
        { [xml](New-OdtInstallXml -ProductId 'A&B<C' -Channel 'X') } | Should -Not -Throw
    }
}
