<#
    Étape « install » (rang 6) et étape « update-drivers » (rang 9) en mode réel, adaptateurs
    système remplacés par des simulacres : outil du constructeur détecté, dépendance .NET,
    lien direct, commande de mise à jour des pilotes et du BIOS (DEC25, DEC26, DEC29).
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }

    function Invoke-Catalog($Context, [string[]]$Id, [string]$Manufacturer = 'Dell Inc.', [switch]$Drivers) {
        $selection = New-Selection
        $selection.Catalog.Ids = $Id
        $selection.Updates.Drivers = [bool]$Drivers
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot -Manufacturer $Manufacturer) -Context $Context
        return (Invoke-ExecutionPlan -Plan $plan -Context $Context)
    }
}

Describe 'Variables de chemin de config.json' {
    It 'ProgramFiles, ProgramFiles(x86), ProgramData et WorkFolder développé' {
        $variables = Get-ConfigPathVariable -Config (Get-TestConfig)
        $variables['ProgramFiles(x86)'] | Should -Be ([Environment]::GetFolderPath('ProgramFilesX86'))
        $variables['WorkFolder'] | Should -Be (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'FastPrepare')
        $lenovo = Get-TestCatalogEntry | Where-Object Id -EQ 'lenovo-thin-installer'
        Expand-ConfigPath -Path $lenovo.Update.FilePath -Variables $variables | Should -Match '^.+\\Lenovo\\ThinInstaller\\ThinInstaller\.exe$'
    }
}

Describe 'Étape install en mode réel — dépendance .NET puis outil du constructeur' {
    BeforeEach {
        Mock @m Assert-WingetAvailable { }
        Mock @m Get-WingetPackageVersion { '5.7.0' }
        Mock @m Install-WingetPackage { [pscustomobject]@{ RebootRequired = $false; AlreadyInstalled = $false } }
        Mock @m Get-DotNetDesktopRuntimeVersion { @() }
    }

    It 'runtime dans la plage déjà présent : rien installé pour .NET, DCU installé' {
        Mock @m Get-DotNetDesktopRuntimeVersion { @('8.0.20') }
        $results = Invoke-Catalog (New-TestContext -Folder $TestDrive -Mode Real) 'dell-command-update'
        @($results.Outcome) | Should -Be @('Succeeded', 'Succeeded')
        Should -Invoke @m Install-WingetPackage -Times 0 -ParameterFilter { $Id -like 'Microsoft.DotNet*' }
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Dell.CommandUpdate.Universal' }
    }
    It 'runtime absent : installé à la version maximale de la plage (DCU 5.7.0 → 8.0.25)' {
        $script:runtimeCalls = 0
        Mock @m Get-DotNetDesktopRuntimeVersion { $script:runtimeCalls++; if ($script:runtimeCalls -eq 1) { @() } else { @('8.0.25') } }
        $results = Invoke-Catalog (New-TestContext -Folder $TestDrive -Mode Real) 'dell-command-update'
        $results[0].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Microsoft.DotNet.DesktopRuntime.8' -and $Version -eq '8.0.25' }
    }
    It 'DCU 5.7.1 : runtime 10 sans borne haute, installé sans version imposée' {
        Mock @m Get-WingetPackageVersion { '5.7.1' }
        $script:runtimeCalls = 0
        Mock @m Get-DotNetDesktopRuntimeVersion { $script:runtimeCalls++; if ($script:runtimeCalls -eq 1) { @() } else { @('10.0.12') } }
        [void](Invoke-Catalog (New-TestContext -Folder $TestDrive -Mode Real) 'dell-command-update')
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Microsoft.DotNet.DesktopRuntime.10' -and -not $Version }
    }
    It 'runtime toujours hors plage après installation : échec, l''outil est quand même tenté' {
        $results = Invoke-Catalog (New-TestContext -Folder $TestDrive -Mode Real) 'dell-command-update'
        $results[0].Outcome | Should -Be 'Failed'
        $results[0].Error | Should -Match 'hors de la plage'
        $results[1].Outcome | Should -Be 'Succeeded'
    }
    It 'runtime plus récent déjà présent : avertissement' {
        Mock @m Get-DotNetDesktopRuntimeVersion { @('8.0.20', '8.0.30') }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        [void](Invoke-Catalog $context 'dell-command-update')
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match 'plus récent.*8\.0\.30'
    }
    It 'version de l''outil inconnue du catalogue : règle de la version inférieure, signalée' {
        Mock @m Get-WingetPackageVersion { '5.9.0' }
        Mock @m Get-DotNetDesktopRuntimeVersion { @('10.0.12') }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        [void](Invoke-Catalog $context 'dell-command-update')
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match '5\.9\.0 absent du catalogue \(DotNet\) : règle de la version 5\.7\.1'
    }
}

Describe 'Étape install en mode réel — un seul chemin de code par nature d''élément' {
    BeforeEach {
        Mock @m Assert-WingetAvailable { }
        Mock @m Install-WingetPackage { [pscustomobject]@{ RebootRequired = $false; AlreadyInstalled = $false } }
        Mock @m Save-RemoteFile { $Destination }
        Mock @m Assert-TrustedExecutable { }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
    }

    It 'Lenovo : deux outils winget (Store et winget), dans l''ordre du catalogue, sans préchargement' {
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $results = Invoke-Catalog $context @('lenovo-commercial-vantage', 'lenovo-thin-installer') -Manufacturer 'LENOVO'
        @($results.Outcome) | Should -Be @('Succeeded', 'Succeeded')
        @($results | ForEach-Object { $_.Action.Parameters.Software.Id }) | Should -Be @('lenovo-commercial-vantage', 'lenovo-thin-installer')
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq '9NR5B8GVVM13' -and $Source -eq 'msstore' }
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Lenovo.ThinInstaller' -and $Source -eq 'winget' }
        Should -Invoke @m Save-RemoteFile -Times 0
    }
    It 'outil constructeur par lien direct : téléchargé dans le cache de l''entrée, signature vérifiée, lancé en silencieux' {
        $context = New-TestContext -Folder (Join-Path $TestDrive 'l1') -Mode Real
        $results = Invoke-Catalog $context 'lenovo-outil-direct' -Manufacturer 'LENOVO'
        $results[0].Outcome | Should -Be 'Succeeded'
        $expected = Join-Path $context.Paths.Cache 'lenovo-outil-direct\OutilSetup.exe'
        Should -Invoke @m Save-RemoteFile -Times 1 -ParameterFilter { $Destination -eq $expected }
        Should -Invoke @m Assert-TrustedExecutable -Times 1 -ParameterFilter { $Path -eq $expected -and $ExpectedSigner -eq 'Lenovo' }
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -eq $expected -and $ArgumentList -eq '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
    }
    It 'signature refusée : rien n''est lancé' {
        Mock @m Assert-TrustedExecutable { throw 'signature non valide' }
        $results = Invoke-Catalog (New-TestContext -Folder (Join-Path $TestDrive 'l2') -Mode Real) 'lenovo-outil-direct' -Manufacturer 'LENOVO'
        $results[0].Outcome | Should -Be 'Failed'
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }
    It 'outil d''un autre constructeur : le plan est refusé, rien n''est installé (DEC25)' {
        $context = New-TestContext -Folder $TestDrive -Mode Real
        { Invoke-Catalog $context 'hp-image-assistant' -Manufacturer 'Dell Inc.' } | Should -Throw '*réservé à un autre constructeur*'
        Should -Invoke @m Install-WingetPackage -Times 0
    }
    It 'constructeur inconnu : aucun outil constructeur, les autres logiciels s''installent' {
        $context = New-TestContext -Folder $TestDrive -Mode Real
        { Invoke-Catalog $context 'dell-command-update' -Manufacturer 'QEMU' } | Should -Throw '*réservé à un autre constructeur*'
        $results = Invoke-Catalog $context 'adobe-reader' -Manufacturer 'QEMU'
        $results[0].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Adobe.Acrobat.Reader.64-bit' }
    }
    It 'catalogue puis Office dans la même étape, numérotée 06/12 dans le journal' {
        Mock @m Initialize-OdtFolder { 'C:\ODT\setup.exe' }
        Mock @m Invoke-Odt { [pscustomobject]@{ RebootRequired = $false; ConfigurationPath = 'C:\ODT\c.xml' } }
        Mock @m Get-OfficeClickToRunProduct { @('O365BusinessRetail') }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $selection = New-Selection
        $selection.Catalog.Ids = @('adobe-reader')
        $selection.Office.EditionKey = 'O365'
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        @($results | ForEach-Object { $_.Action.Parameters.Kind }) | Should -Be @('CatalogInstall', 'OdtInstall')
        @($results.Outcome) | Should -Be @('Succeeded', 'Succeeded')
        $text = (Receive-RunLogEntry -Log $context.Log).Line -join "`n"
        $text | Should -Match '\[ETAPE 06/12\] Adobe Acrobat Reader'
        $text | Should -Match '\[ETAPE 06/12\] Office : '
    }
}

Describe 'Étape update-drivers en mode réel — pilotes et BIOS par l''outil du constructeur' {
    BeforeEach {
        Mock @m Assert-WingetAvailable { }
        Mock @m Get-WingetPackageVersion { '5.7.0' }
        Mock @m Install-WingetPackage { [pscustomobject]@{ RebootRequired = $false; AlreadyInstalled = $true } }
        Mock @m Get-DotNetDesktopRuntimeVersion { @('8.0.20') }
        Mock @m Find-InstalledExecutable { 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe' }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 1; RebootRequired = $true } }
    }
    It 'chemin développé, codes de succès et de redémarrage du catalogue, redémarrage signalé' {
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $results = Invoke-Catalog $context 'dell-command-update' -Drivers
        $results[-1].Action.StepId | Should -Be 'update-drivers'
        $results[-1].Outcome | Should -Be 'Succeeded'
        $results[-1].RebootRequired | Should -BeTrue
        Should -Invoke @m Find-InstalledExecutable -Times 1 -ParameterFilter { $Path -eq 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe' }
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter {
            $ArgumentList -eq '/applyUpdates -reboot=disable' -and (@($SuccessExitCode) -join ',') -eq '0,500' -and (@($RebootExitCode) -join ',') -eq '1,5'
        }
    }
    It 'codes de redémarrage absents du catalogue : 3010 et 1641 par défaut' {
        Mock @m Find-InstalledExecutable { 'C:\Fujitsu\ducmd.exe' }
        [void](Invoke-Catalog (New-TestContext -Folder $TestDrive -Mode Real) 'fujitsu-deskupdate' -Manufacturer 'FUJITSU' -Drivers)
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $ArgumentList -eq '/WEB /DRV /BIOS' -and (@($RebootExitCode) -join ',') -eq '3010,1641' }
    }
    It 'case décochée : l''outil est installé, aucune mise à jour lancée' {
        $results = Invoke-Catalog (New-TestContext -Folder $TestDrive -Mode Real) 'dell-command-update'
        @($results | Where-Object { $_.Action.StepId -eq 'update-drivers' }).Count | Should -Be 0
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }
    It 'outil introuvable : échec explicite' {
        Mock @m Find-InstalledExecutable { throw 'Outil « HPImageAssistant.exe » introuvable' }
        $results = Invoke-Catalog (New-TestContext -Folder $TestDrive -Mode Real) 'hp-image-assistant' -Manufacturer 'HP' -Drivers
        $results[-1].Outcome | Should -Be 'Failed'
        $results[-1].Error | Should -Match 'introuvable'
    }
}
