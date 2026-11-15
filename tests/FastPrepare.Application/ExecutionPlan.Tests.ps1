BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application

    function New-FullSelection {
        $s = New-Selection
        $s.HostName.Enabled = $true; $s.HostName.Name = 'PC-01'
        $s.Software.Items = @(
            [pscustomobject]@{ Name = 'Zeta assistant'; Silent = $false; Method = 'Assistant'; Command = 'C:\Z\setup.exe /remove' }
            [pscustomobject]@{ Name = 'Alpha muet'; Silent = $true; Method = 'MSI'; Command = 'msiexec.exe /x {GUID} /qn /norestart' }
        )
        foreach ($p in 'OfficeClickToRun', 'OfficeMsi', 'OutlookClassic', 'OutlookNew', 'OneNote', 'Teams', 'OneDrive', 'OneDriveFolder') { $s.MicrosoftApps.$p = $true }
        $s.LocalAccounts.Items = @((New-TestSnapshot).LocalAccounts.Removable)
        $s.Catalog.Ids = @('dell-command-update', 'adobe-reader')
        $s.Office.EditionKey = 'O365'; $s.Office.IncludedApps = @('OutlookForWindows', 'Outlook', 'OneDrive')
        $s.Updates.WindowsUpdate = $true; $s.Updates.Drivers = $true
        $s.SystemSettings.Ipv6Adapters = @((New-TestSnapshot).Adapters)
        $s.SystemSettings.Power = $true
        return $s
    }
}

Describe 'New-ExecutionPlan' {
    BeforeEach { $context = New-TestContext -Folder $TestDrive }

    It 'sélection vide : plan vide, 12 étapes connues' {
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        @($plan.Actions).Count | Should -Be 0
        $plan.StepCount | Should -Be 12
    }

    It 'actions dans l''ordre d''exécution, quel que soit l''ordre des sections, numérotées 1..N' {
        $plan = New-ExecutionPlan -Selection (New-FullSelection) -Snapshot (New-TestSnapshot) -Context $context
        $numbers = @($plan.Actions | ForEach-Object StepNumber)
        ($numbers -join ',') | Should -Be (($numbers | Sort-Object) -join ',')
        @($plan.Actions | ForEach-Object Index) | Should -Be (1..@($plan.Actions).Count)
        $plan.Actions[0].StepId | Should -Be 'remove-local-accounts'
        $plan.Actions[-1].StepId | Should -Be 'rename-computer'
    }

    It 'sélection complète : actions attendues par étape' {
        $plan = New-ExecutionPlan -Selection (New-FullSelection) -Snapshot (New-TestSnapshot) -Context $context
        $byStep = $plan.Actions | Group-Object StepId -AsHashTable
        $byStep['remove-local-accounts'].Count | Should -Be 1
        $byStep['remove-microsoft-apps'].Count | Should -Be 7     # ODT + nouvel Outlook + OneNote + 4 Teams
        $byStep['remove-onedrive'].Count | Should -Be 3
        $byStep['uninstall-software'].Count | Should -Be 2
        $byStep['install'].Count | Should -Be 4                   # .NET + DCU, Adobe Reader, Office
        $byStep['disable-ipv6'].Count | Should -Be 1              # le Wi-Fi a déjà IPv6 désactivé
        $byStep['set-power-plan'].Count | Should -Be 1
        $byStep['update-drivers'].Count | Should -Be 1
        $byStep['run-windows-update'].Count | Should -Be 1
        $byStep['rename-computer'].Count | Should -Be 1
        $byStep.ContainsKey('export-inventory') | Should -BeFalse  # exporté au démarrage
    }

    It 'désinstallations : silencieuses d''abord, assistants en dernier et marqués interactifs' {
        $plan = New-ExecutionPlan -Selection (New-FullSelection) -Snapshot (New-TestSnapshot) -Context $context
        $uninstall = @($plan.Actions | Where-Object StepId -EQ 'uninstall-software')
        $uninstall[0].Parameters.Name | Should -Be 'Alpha muet'
        $uninstall[0].Interactive | Should -BeFalse
        $uninstall[1].Interactive | Should -BeTrue
    }

    It 'Office : un seul passage ODT de suppression, XML en détail, puis installation 365 sans Teams' {
        $selection = New-FullSelection
        $selection.Office.WithoutTeams = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $remove = $plan.Actions | Where-Object { $_.Parameters.Kind -eq 'OdtRemove' }
        @($remove).Count | Should -Be 1
        ($remove.Details -join "`n") | Should -Match 'Remove All="TRUE"'
        ($remove.Details -join "`n") | Should -Match 'RemoveMSI'
        $install = $plan.Actions | Where-Object { $_.Parameters.Kind -eq 'OdtInstall' }
        $install.Parameters.Xml | Should -Match 'O365BusinessEEANoTeamsRetail'
    }

    It 'étape install : catalogue dans l''ordre du fichier (dépendance .NET juste avant son outil), Office en dernier' {
        $plan = New-ExecutionPlan -Selection (New-FullSelection) -Snapshot (New-TestSnapshot) -Context $context
        $install = @($plan.Actions | Where-Object StepId -EQ 'install')
        @($install | ForEach-Object { $_.Parameters.Kind }) | Should -Be @('DotNetDependency', 'CatalogInstall', 'CatalogInstall', 'OdtInstall')
        $install[0].Parameters.Software.Id | Should -Be 'dell-command-update'
        $install[1].Parameters.Software.Id | Should -Be 'dell-command-update'
        $install[2].Parameters.Software.Id | Should -Be 'adobe-reader'
        @($install | ForEach-Object StepNumber | Sort-Object -Unique) | Should -Be @(6)
    }

    It 'outil d''un autre constructeur : plan refusé (DEC25)' {
        $selection = New-Selection
        $selection.Catalog.Ids = @('hp-image-assistant')
        { New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context } | Should -Throw '*réservé à un autre constructeur*'
    }

    It 'pilotes et BIOS : une action par outil coché qui porte une commande Update' {
        $selection = New-Selection
        $selection.Catalog.Ids = @('lenovo-commercial-vantage', 'lenovo-thin-installer')
        $selection.Updates.Drivers = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot -Manufacturer 'LENOVO') -Context $context
        $update = @($plan.Actions | Where-Object StepId -EQ 'update-drivers')
        $update.Count | Should -Be 1
        $update[0].Label | Should -Match 'Lenovo Thin Installer'
        $update[0].StepNumber | Should -Be 9
    }

    It 'avertissements : Outlook classique seul, OneNote sans Click-to-Run' {
        $selection = New-Selection
        $selection.MicrosoftApps.OutlookClassic = $true
        $selection.MicrosoftApps.OneNote = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        @($plan.Warnings).Count | Should -Be 2
        ($plan.Warnings -join "`n") | Should -Match 'QO1'
        @($plan.Actions).Count | Should -Be 1   # seule l'application OneNote du Store
    }

    It 'inventaire : action de nouvel essai seulement si l''export du démarrage a échoué' {
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot -InventoryExportFailed) -Context $context
        $plan.Actions[0].StepId | Should -Be 'export-inventory'
        $plan.Actions[0].StepNumber | Should -Be 1
    }

    It 'dossier OneDrive absent : avertissement, pas d''action de suppression' {
        $snapshot = New-TestSnapshot
        $snapshot.OneDrive.Exists = $false
        $selection = New-Selection
        $selection.MicrosoftApps.OneDrive = $true; $selection.MicrosoftApps.OneDriveFolder = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot $snapshot -Context $context
        @($plan.Actions | Where-Object { $_.Parameters.Kind -eq 'RemoveFolder' }).Count | Should -Be 0
        ($plan.Warnings -join "`n") | Should -Match 'absent'
    }

    It 'alimentation secteur seulement quand ApplyOnBattery est faux' {
        $config = Get-TestConfig
        $config.Power.ApplyOnBattery = $false
        $context = New-TestContext -Folder $TestDrive -Config $config
        $selection = New-Selection; $selection.SystemSettings.Power = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $plan.Actions[0].Label | Should -Match 'monitor-timeout-ac 5'
        $plan.Actions[0].Label | Should -Not -Match '-dc'
    }

    It 'sélection incohérente : plan refusé' {
        $selection = New-Selection
        $selection.Updates.Drivers = $true
        { New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context } | Should -Throw '*incohérente*'
    }

    It 'actions sans objet graphique ni scriptblock (transmissibles au runspace d''exécution)' {
        $plan = New-ExecutionPlan -Selection (New-FullSelection) -Snapshot (New-TestSnapshot) -Context $context
        foreach ($action in $plan.Actions) {
            foreach ($value in $action.Parameters.Values) {
                $value | Should -Not -BeOfType [scriptblock]
                $value.GetType().FullName | Should -Not -Match '^System\.Windows'
            }
        }
    }
}

Describe 'Format-ExecutionPlanSummary' {
    It 'compte les actions et les assistants' {
        $context = New-TestContext -Folder $TestDrive
        $plan = New-ExecutionPlan -Selection (New-FullSelection) -Snapshot (New-TestSnapshot) -Context $context
        Format-ExecutionPlanSummary -Plan $plan | Should -Match '^\d+ action\(s\), dont 1 avec assistant'
    }
}
