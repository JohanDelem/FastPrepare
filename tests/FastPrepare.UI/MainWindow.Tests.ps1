<#
    Fenêtre construite sans être affichée (Initialize-MainWindow), relevé de poste fictif :
    sections dans l'ordre d'exécution, section « Installations » limitée au constructeur détecté
    (DEC25 à DEC27). Aucune action n'est lancée, aucun accès réseau.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Add-Type -AssemblyName PresentationFramework

    function New-TestWindow([string]$Manufacturer) {
        # Module rechargé : le registre des sections et l'état de la fenêtre repartent de zéro.
        Import-FastPrepareModule Core, Infrastructure, Application, UI
        $context = New-TestContext -Folder (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $context | Add-Member -NotePropertyName Root -NotePropertyValue (Get-RepoRoot)
        $snapshot = New-TestSnapshot -Manufacturer $Manufacturer
        InModuleScope FastPrepare.UI -Parameters @{ Context = $context; Snapshot = $snapshot } {
            param($Context, $Snapshot)
            [void](Initialize-MainWindow -Context $Context)
            Complete-MachineView -Snapshot $Snapshot
        }
        return $context
    }
    function Get-InstallCheck {
        InModuleScope FastPrepare.UI { @((Get-UiSection -Id 'install').State.Checks | ForEach-Object { [string]$_.Tag }) }
    }
    function Close-TestWindow {
        InModuleScope FastPrepare.UI { foreach ($section in (Get-UiSection)) { Invoke-UiSectionCallback -Section $section -Name Dispose | Out-Null } }
    }
}

Describe 'Fenêtre — sections' {
    BeforeAll { $context = New-TestWindow 'Dell Inc.' }
    AfterAll { Close-TestWindow }

    It 'neuf sections numérotées dans l''ordre d''exécution, numéro calculé (jamais écrit dans le XAML)' {
        $titles = InModuleScope FastPrepare.UI { @(Get-UiSection | Where-Object { $_.Column -in 'Left', 'Right' } | ForEach-Object { $_.Controls.TxtTitle.Text }) }
        $titles | Should -Be @(
            '1 · Numéro de série et adresses MAC'
            '2 · Suppression des sessions locales'
            '3 · Désinstallation des programmes Microsoft'
            '4 · Désinstallation des logiciels installés'
            '5 · Installations'
            '6 · Configuration des paramètres système'
            '7 · Mises à jour'
            "8 · Changer le nom d'hôte"
            '9 · Créer une session locale'
        )
    }

    It 'aucun fragment XAML ne porte de numéro de section' {
        foreach ($file in (Get-ChildItem -Path (Join-Path (Get-RepoRoot) 'src\FastPrepare.UI\Xaml\Sections') -Filter '*.xaml')) {
            [System.IO.File]::ReadAllText($file.FullName) | Should -Not -Match 'Text="\d+ · '
        }
    }

    It 'titre de la fenêtre : nom de l''outil et version' {
        InModuleScope FastPrepare.UI { $script:Shell.Root.Title } | Should -Be 'FastPrepare 0.0.0 — Préparation de poste'
    }

    It 'la sélection de la fenêtre produit un plan cohérent' {
        $plan = InModuleScope FastPrepare.UI { New-ExecutionPlan -Selection (Get-CurrentSelection) -Snapshot $script:Snapshot -Context $script:Context }
        @($plan.Actions | Where-Object StepId -EQ 'install' | ForEach-Object { $_.Parameters.Kind }) | Should -Be @('DotNetDependency', 'CatalogInstall', 'CatalogInstall')
        @($plan.Actions | Where-Object StepId -EQ 'update-drivers').Count | Should -Be 1
    }
}

Describe 'Fenêtre — outil du constructeur détecté seulement (DEC25)' {
    AfterEach { Close-TestWindow }

    It '<Manufacturer> : <Expected>' -ForEach @(
        @{ Manufacturer = 'Dell Inc.'; Expected = 'dell-command-update,adobe-reader' }
        @{ Manufacturer = 'Hewlett-Packard'; Expected = 'hp-image-assistant,adobe-reader' }
        @{ Manufacturer = 'LENOVO'; Expected = 'lenovo-commercial-vantage,lenovo-thin-installer,lenovo-outil-direct,adobe-reader' }
        @{ Manufacturer = 'QEMU'; Expected = 'adobe-reader' }
        @{ Manufacturer = ''; Expected = 'adobe-reader' }
    ) {
        [void](New-TestWindow $Manufacturer)
        (Get-InstallCheck) -join ',' | Should -Be $Expected
    }

    It 'outil constructeur coché par défaut : mise à jour des pilotes proposée et cochée ; décoché : masquée' {
        [void](New-TestWindow 'Dell Inc.')
        $state = InModuleScope FastPrepare.UI {
            $check = (Get-UiSection -Id 'updates').Controls.ChkDrivers
            $before = [pscustomobject]@{ Visibility = [string]$check.Visibility; Content = [string]$check.Content; Drivers = (Get-CurrentSelection).Updates.Drivers }
            ((Get-UiSection -Id 'install').State.Checks | Where-Object { $_.Tag -eq 'dell-command-update' }).IsChecked = $false
            Update-UiState
            [pscustomobject]@{ Before = $before; After = [string]$check.Visibility; Drivers = (Get-CurrentSelection).Updates.Drivers }
        }
        $state.Before.Visibility | Should -Be 'Visible'
        $state.Before.Content | Should -Be 'Mettre à jour les pilotes et le BIOS (Dell Command Update)'
        $state.Before.Drivers | Should -BeTrue
        $state.After | Should -Be 'Collapsed'
        $state.Drivers | Should -BeFalse
    }

    It 'constructeur inconnu : aucune mise à jour des pilotes proposée' {
        [void](New-TestWindow 'QEMU')
        InModuleScope FastPrepare.UI { [string](Get-UiSection -Id 'updates').Controls.ChkDrivers.Visibility } | Should -Be 'Collapsed'
        InModuleScope FastPrepare.UI { (Get-UiSection -Id 'install').Controls.TxtVendorInfo.Text } | Should -Match 'aucun outil constructeur'
    }

    It 'onglet Réglages : tout le catalogue, quel que soit le poste ; champs avancés repris à l''enregistrement' {
        [void](New-TestWindow 'QEMU')
        $form = InModuleScope FastPrepare.UI {
            $section = Get-UiSection -Id 'software-catalog-settings'
            $count = $section.Controls.LstSw.Items.Count
            $section.Controls.LstSw.SelectedIndex = 0
            Open-SoftwareCatalogSelection
            $entry = (Get-SoftwareFormEntry).Entry
            [pscustomobject]@{ Count = $count; Manufacturer = $section.Controls.TxtSwManufacturer.Text; Entry = $entry; Problems = @((Get-SoftwareFormEntry).Problems) }
        }
        $form.Count | Should -Be @(Get-TestCatalogEntry).Count
        $form.Manufacturer | Should -Be 'Dell'
        $form.Entry.Id | Should -Be 'dell-command-update'
        @($form.Entry.DotNet).Count | Should -Be 2
        $form.Entry.Update.FilePath | Should -Match 'dcu-cli\.exe$'
        $form.Problems.Count | Should -Be 0
    }
}
