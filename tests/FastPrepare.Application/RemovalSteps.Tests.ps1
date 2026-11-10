<#
    Étapes de désinstallation (itération 4) en mode réel, adaptateurs remplacés par des simulacres.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }
    $profiles = [pscustomobject]@{ Root = 'C:\Users'; Current = 'C:\Users\technicien'; Default = 'C:\Users\Default' }
}

Describe 'Mode réel — désinstallations' {
    BeforeEach {
        Mock @m Get-ProfileLocation { $profiles }
        Mock @m Get-CurrentUserSid { 'S-1-5-21-1-2-3-1001' }
        Mock @m Remove-LocalAccountWithProfile { [pscustomobject]@{ AccountRemoved = $true; ProfileRemoved = $true; LeftoverFolder = $null } }
        Mock @m Initialize-OdtFolder { 'C:\ODT\setup.exe' }
        Mock @m Invoke-Odt { [pscustomobject]@{ RebootRequired = $false; ConfigurationPath = 'C:\ODT\c.xml' } }
        Mock @m Remove-AppxEverywhere { [pscustomobject]@{ Installed = @('x'); Provisioned = @() } }
        Mock @m Get-MsiProductCodeByName { '{11111111-2222-3333-4444-555555555555}' }
        Mock @m Uninstall-MsiProduct { [pscustomobject]@{ RebootRequired = $false } }
        Mock @m Remove-GuardedFolder { [pscustomobject]@{ Changed = $true } }
        Mock @m Stop-ProcessByName { 0 }
        Mock @m Uninstall-OneDrive { [pscustomobject]@{ Changed = $true } }
        Mock @m Remove-DefaultProfileOneDriveRun { [pscustomobject]@{ Changed = $true } }
        Mock @m Invoke-UninstallCommand { [pscustomobject]@{ RebootRequired = $false } }
        Mock @m Wait-UninstallEntryRemoval { $true }
        $context = New-TestContext -Folder $TestDrive -Mode Real
    }

    It 'sections 2 à 4 cochées : toutes les actions réussissent, dans l''ordre du cahier' {
        $selection = New-Selection
        $selection.LocalAccounts.Items = @((New-TestSnapshot).LocalAccounts.Removable)
        foreach ($p in 'OfficeClickToRun', 'OfficeMsi', 'OutlookClassic', 'OutlookNew', 'OneNote', 'Teams', 'OneDrive', 'OneDriveFolder') { $selection.MicrosoftApps.$p = $true }
        $selection.Software.Items = @(
            [pscustomobject]@{ Name = 'Assistant'; Version = '2'; Silent = $false; Method = 'Assistant'; Command = 'C:\A\setup.exe /remove' }
            [pscustomobject]@{ Name = 'Muet'; Version = '1'; Silent = $true; Method = 'MSI'; Command = 'msiexec.exe /x {GUID} /qn /norestart' }
        )
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context

        @($results | Where-Object Outcome -NE 'Succeeded') | Should -BeNullOrEmpty
        Should -Invoke @m Remove-LocalAccountWithProfile -Times 1 -ParameterFilter { $Sid -eq 'S-1-5-21-1-2-3-1002' }
        Should -Invoke @m Invoke-Odt -Times 1 -ParameterFilter { $Xml -match 'Remove All="TRUE"' -and $Xml -match 'RemoveMSI' }
        Should -Invoke @m Remove-AppxEverywhere -Times 4    # nouvel Outlook, OneNote, MSTeams, MicrosoftTeams
        Should -Invoke @m Uninstall-MsiProduct -Times 1
        Should -Invoke @m Remove-GuardedFolder -Times 1 -ParameterFilter { $Path -eq 'C:\Users\technicien\AppData\Local\Microsoft\Teams' -and $AllowInsideProfile }
        Should -Invoke @m Remove-GuardedFolder -Times 1 -ParameterFilter { $Path -eq 'C:\Users\technicien\OneDrive' -and $AllowInsideProfile }
        Should -Invoke @m Remove-DefaultProfileOneDriveRun -Times 1 -ParameterFilter { $DefaultProfilePath -eq 'C:\Users\Default' }
        Should -Invoke @m Invoke-UninstallCommand -Times 1 -ParameterFilter { $Command -like 'msiexec*' -and -not $Interactive }
        Should -Invoke @m Invoke-UninstallCommand -Times 1 -ParameterFilter { $Command -like 'C:\A\setup.exe*' -and $Interactive }
    }

    It 'compte devenu protégé au moment d''exécuter (session ouverte entre-temps) : refus' {
        Mock @m Get-CurrentUserSid { 'S-1-5-21-1-2-3-1002' }
        $selection = New-Selection
        $selection.LocalAccounts.Items = @((New-TestSnapshot).LocalAccounts.Removable)
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[0].Outcome | Should -Be 'Failed'
        $results[0].Error | Should -Match 'protégé'
        Should -Invoke @m Remove-LocalAccountWithProfile -Times 0
    }

    It 'profil hors du dossier des profils : refus par la garde de chemin' {
        $snapshot = New-TestSnapshot
        $snapshot.LocalAccounts.Removable[0].ProfilePath = 'C:\Windows'
        $selection = New-Selection
        $selection.LocalAccounts.Items = @($snapshot.LocalAccounts.Removable)
        $plan = New-ExecutionPlan -Selection $selection -Snapshot $snapshot -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[0].Error | Should -Match 'garde de chemin'
        Should -Invoke @m Remove-LocalAccountWithProfile -Times 0
    }

    It 'logiciel encore présent après l''assistant (annulé) : échec signalé' {
        Mock @m Wait-UninstallEntryRemoval { $false }
        $selection = New-Selection
        $selection.Software.Items = @([pscustomobject]@{ Name = 'Tenace'; Version = '1'; Silent = $false; Method = 'Assistant'; Command = 'C:\T\u.exe' })
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[0].Outcome | Should -Be 'Failed'
        $results[0].Error | Should -Match 'toujours présent'
    }

    It 'Teams Machine-Wide Installer absent : succès, rien désinstallé' {
        Mock @m Get-MsiProductCodeByName { }
        $selection = New-Selection
        $selection.MicrosoftApps.Teams = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        @($results | Where-Object Outcome -NE 'Succeeded') | Should -BeNullOrEmpty
        Should -Invoke @m Uninstall-MsiProduct -Times 0
    }

    It 'logiciel sans commande de désinstallation : avertissement, pas d''action' {
        $selection = New-Selection
        $selection.Software.Items = @([pscustomobject]@{ Name = 'Orphelin'; Version = '1'; Silent = $false; Method = 'Aucune commande'; Command = $null })
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        @($plan.Actions).Count | Should -Be 0
        ($plan.Warnings -join "`n") | Should -Match 'Orphelin'
    }
}
