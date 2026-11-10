BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application

    $config = Get-TestConfig
    function New-TestContext {
        $log = New-RunLog -Folder (Join-Path $TestDrive 'logs') -FallbackFolder (Join-Path $TestDrive 'repli') -HostName 'PC1' -Stamp 'test'
        return [pscustomobject]@{ Config = $config; Mode = 'Simulation'; Stamp = 'test'; Log = $log; Paths = [pscustomobject]@{ Logs = $log.Folder } }
    }
    $snapshot = [pscustomobject]@{ OneDrive = [pscustomobject]@{ Path = 'C:\Users\tech\OneDrive' } }
}

Describe 'Invoke-SelectionSimulation (transitoire, itération 0)' {
    It 'sélection vide : aucune action, rappels manuels issus de la configuration' {
        $context = New-TestContext
        Invoke-SelectionSimulation -Selection (New-Selection) -Snapshot $snapshot -Context $context | Should -Be 0
        $lines = @(Receive-RunLogEntry -Log $context.Log).Line
        $lines[-1] | Should -Match ([regex]::Escape(($config.ManualReminders -join ' · ')))
    }

    It 'actions journalisées dans l''ordre du cahier, quel que soit l''ordre des sections' {
        $context = New-TestContext
        $selection = New-Selection
        $selection.HostName.Enabled = $true
        $selection.HostName.Name = 'PC-01'
        $selection.Updates.WindowsUpdate = $true
        $selection.SystemSettings.Power = $true
        $selection.MicrosoftApps.OneDrive = $true
        $selection.Software.Items = @(
            [pscustomobject]@{ Name = 'Assistant'; Silent = $false; Method = 'Assistant'; Command = 'x.exe' }
            [pscustomobject]@{ Name = 'Muet'; Silent = $true; Method = 'MSI'; Command = 'msiexec' }
        )
        $selection.VendorUtility.Key = 'dell'
        $selection.Updates.VendorUtility = $true
        $selection.Office.EditionKey = 'O365'
        $selection.Office.IncludedApps = @('Outlook', 'OneDrive', 'OutlookForWindows')
        $selection.ExtraSoftware.Ids = @('adobe-reader')

        $count = Invoke-SelectionSimulation -Selection $selection -Snapshot $snapshot -Context $context
        $lines = @(Receive-RunLogEntry -Log $context.Log | ForEach-Object { $_.Line -replace '^\S+ \[\w+\] ', '' })
        $numbers = @($lines | Where-Object { $_ -match '^(\d+)\. ' } | ForEach-Object { [int]($_ -replace '^(\d+)\..*', '$1') })
        ($numbers -join ',') | Should -Be (($numbers | Sort-Object) -join ',')
        $count | Should -Be 11

        $silentIndex = [array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -like '5. Désinstallation silencieuse*' })
        $wizardIndex = [array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -like '5. Désinstallation avec assistant*' })
        $silentIndex | Should -BeLessThan $wizardIndex
        $lines | Should -Contain "13. Nom d'hôte : Rename-Computer -NewName 'PC-01' (pris en compte au redémarrage)"
    }

    It 'Office 365 sans Teams : ID produit EEA dans le XML journalisé' {
        $context = New-TestContext
        $selection = New-Selection
        $selection.Office.EditionKey = 'O365'
        $selection.Office.WithoutTeams = $true
        [void](Invoke-SelectionSimulation -Selection $selection -Snapshot $snapshot -Context $context)
        (@(Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match 'O365BusinessEEANoTeamsRetail'
    }

    It 'alimentation secteur seulement quand ApplyOnBattery est faux' {
        $context = New-TestContext
        $context.Config = Get-TestConfig
        $context.Config.Power.ApplyOnBattery = $false
        $selection = New-Selection
        $selection.SystemSettings.Power = $true
        [void](Invoke-SelectionSimulation -Selection $selection -Snapshot $snapshot -Context $context)
        $text = @(Receive-RunLogEntry -Log $context.Log).Line -join "`n"
        $text | Should -Match 'monitor-timeout-ac 5'
        $text | Should -Not -Match '-dc'
    }
}
