<#
    Installation d'Office (itération 6) en mode réel, adaptateurs remplacés par des simulacres.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }
    function Invoke-Office($Context, [string]$Key, [switch]$WithoutTeams, [string[]]$Included = @('OutlookForWindows', 'Outlook', 'OneDrive')) {
        $selection = New-Selection
        $selection.Office.EditionKey = $Key
        $selection.Office.WithoutTeams = [bool]$WithoutTeams
        $selection.Office.IncludedApps = $Included
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $Context
        return (Invoke-ExecutionPlan -Plan $plan -Context $Context)
    }
}

Describe 'Étape 7 en mode réel — Office via ODT' {
    BeforeEach {
        Mock @m Initialize-OdtFolder { 'C:\ODT\setup.exe' }
        Mock @m Invoke-Odt { [pscustomobject]@{ RebootRequired = $false; ConfigurationPath = 'C:\ODT\c.xml' } }
    }

    It '<Key> : XML de l''édition passé à ODT, produit vérifié après installation' -ForEach @(
        @{ Key = 'O365'; ProductId = 'O365BusinessRetail' }
        @{ Key = 'LTSC2024'; ProductId = 'ProPlus2024Volume' }
        @{ Key = 'STD2019'; ProductId = 'Standard2019Volume' }
        @{ Key = 'PP2019'; ProductId = 'ProPlus2019Volume' }
    ) {
        $expected = $ProductId
        Mock @m Get-OfficeClickToRunProduct { @($expected) }
        $results = Invoke-Office (New-TestContext -Folder $TestDrive -Mode Real) $Key
        $results[0].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Invoke-Odt -Times 1 -ParameterFilter { $Name -eq 'installation' -and $Xml -match "Product ID=`"$expected`"" -and $SetupPath -eq 'C:\ODT\setup.exe' }
        Should -Invoke @m Initialize-OdtFolder -Times 1 -ParameterFilter { $Folder -eq 'C:\ODT' -and $SetupUrl -like 'https://*' }
    }

    It '365 sans Teams et sans OneDrive : ID EEA et ExcludeApp OneDrive' {
        Mock @m Get-OfficeClickToRunProduct { @('O365BusinessEEANoTeamsRetail') }
        $results = Invoke-Office (New-TestContext -Folder $TestDrive -Mode Real) 'O365' -WithoutTeams -Included @('OutlookForWindows', 'Outlook')
        $results[0].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Invoke-Odt -Times 1 -ParameterFilter { $Xml -match 'O365BusinessEEANoTeamsRetail' -and $Xml -match 'ExcludeApp ID="OneDrive"' -and $Xml -notmatch 'Teams"' }
    }

    It 'ODT terminé sans le produit attendu : échec explicite' {
        Mock @m Get-OfficeClickToRunProduct { @() }
        $results = Invoke-Office (New-TestContext -Folder $TestDrive -Mode Real) 'O365'
        $results[0].Outcome | Should -Be 'Failed'
        $results[0].Error | Should -Match 'O365BusinessRetail absent.*aucun'
    }

    It 'XML recopié dans le journal (traçabilité de ce qui a été installé)' {
        Mock @m Get-OfficeClickToRunProduct { @('O365BusinessRetail') }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        [void](Invoke-Office $context 'O365')
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match '<Product ID="O365BusinessRetail">'
    }

    It 'suppression puis installation dans la même exécution : deux passages ODT, suppression d''abord' {
        Mock @m Remove-AppxEverywhere { [pscustomobject]@{ Installed = @(); Provisioned = @() } }
        Mock @m Stop-ProcessByName { 0 }
        Mock @m Get-OfficeClickToRunProduct { @('O365BusinessRetail') }
        $script:odtOrder = New-Object System.Collections.Generic.List[string]
        Mock @m Invoke-Odt { $script:odtOrder.Add($Name); [pscustomobject]@{ RebootRequired = $false } }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $selection = New-Selection
        $selection.MicrosoftApps.OfficeClickToRun = $true
        $selection.Office.EditionKey = 'O365'
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        @($results | Where-Object Outcome -NE 'Succeeded') | Should -BeNullOrEmpty
        @($script:odtOrder) | Should -Be @('suppression', 'installation')
    }
}
