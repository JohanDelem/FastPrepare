<#
    Étapes disponibles en mode réel (itération 3), de bout en bout : plan construit par les
    étapes, moteur en mode réel, adaptateurs système remplacés par des simulacres.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }
}

Describe 'Mode réel — étapes de l''itération 3' {
    BeforeEach {
        Mock @m Assert-WingetAvailable { }
        Mock @m Install-WingetPackage { [pscustomobject]@{ RebootRequired = $false; AlreadyInstalled = $false } }
        Mock @m Disable-AdapterIpv6 { [pscustomobject]@{ Changed = $true } }
        Mock @m Set-PowerTimeout { }
        Mock @m Rename-LocalComputer { [pscustomobject]@{ Changed = $true; RebootRequired = $true } }
        Mock @m Export-MachineInventory { [pscustomobject]@{ Path = 'C:\x.txt'; Error = $null } }
        $context = New-TestContext -Folder $TestDrive -Mode Real
    }

    It 'alimentation, IPv6, logiciel, nom d''hôte : exécutés avec les bons paramètres' {
        $selection = New-Selection
        $selection.SystemSettings.Power = $true
        $selection.SystemSettings.Ipv6Adapters = @((New-TestSnapshot).Adapters)
        $selection.ExtraSoftware.Ids = @('adobe-reader')
        $selection.HostName.Enabled = $true; $selection.HostName.Name = 'PC-0042'
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context

        @($results | Where-Object Outcome -NE 'Succeeded').Count | Should -Be 0
        Should -Invoke @m Assert-WingetAvailable -Times 1 -ParameterFilter { $OfflineBundle -eq 'C:\Cle\packages\winget.msixbundle' }
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Adobe.Acrobat.Reader.64-bit' -and $Override -eq '-sfx_nu /sAll /rs /msi' }
        Should -Invoke @m Disable-AdapterIpv6 -Times 1 -ParameterFilter { $Name -eq 'Ethernet' }
        Should -Invoke @m Set-PowerTimeout -Times 1 -ParameterFilter { $MonitorMinutes -eq 5 -and $StandbyMinutes -eq 15 -and $IncludeBattery }
        Should -Invoke @m Rename-LocalComputer -Times 1 -ParameterFilter { $NewName -eq 'PC-0042' }
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match 'Redémarrage nécessaire'
    }

    It 'étapes pas encore disponibles en réel : ignorées et signalées, rien d''exécuté' {
        $selection = New-Selection
        $selection.Office.EditionKey = 'O365'
        $selection.Updates.WindowsUpdate = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        Format-ExecutionPlanSummary -Plan $plan | Should -Match '2 non disponible\(s\) en mode réel'
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        @($results | Where-Object Outcome -NE 'Skipped').Count | Should -Be 0
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match '2 ignorée\(s\)'
    }

    It 'un échec (winget) n''empêche pas les actions suivantes' {
        Mock @m Install-WingetPackage { throw '« winget.exe » : code de sortie 1603' }
        $selection = New-Selection
        $selection.ExtraSoftware.Ids = @('adobe-reader')
        $selection.SystemSettings.Power = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        @($results).Outcome | Should -Be @('Failed', 'Succeeded')
        Should -Invoke @m Set-PowerTimeout -Times 1
    }

    It 'inventaire : nouvel essai d''export si celui du démarrage a échoué' {
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot -InventoryExportFailed) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[0].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Export-MachineInventory -Times 1 -ParameterFilter { $Snapshot.Identity.Serial -eq 'SN0000TEST' }
    }
}
