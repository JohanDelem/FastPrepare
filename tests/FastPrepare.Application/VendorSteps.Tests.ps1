<#
    Utilitaire constructeur (itération 5) : préchargement, dépendance .NET, installation, mise à jour.
    Adaptateurs système remplacés par des simulacres ; le cache est un dossier de test réel.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }

    function New-LenovoConfig {
        $config = Get-TestConfig
        $config.Utilities.lenovo.Install[1].Url = 'https://exemple.test/thin.exe'
        return $config
    }
    function Invoke-Vendor($Context, [string]$Key, [switch]$Update) {
        $selection = New-Selection
        $selection.VendorUtility.Key = $Key
        $selection.Updates.VendorUtility = [bool]$Update
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $Context
        return (Invoke-ExecutionPlan -Plan $plan -Context $Context)
    }
}

Describe 'Variables de chemin de config.json' {
    It 'ProgramFiles, ProgramFiles(x86), ProgramData, OdtFolder et CacheFolder développé' {
        $variables = Get-ConfigPathVariable -Config (Get-TestConfig)
        $variables['ProgramFiles(x86)'] | Should -Be ([Environment]::GetFolderPath('ProgramFilesX86'))
        $variables['CacheFolder'] | Should -Be (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'FastPrepare\cache')
        Expand-ConfigPath -Path (Get-TestConfig).Utilities.lenovo.Update.FilePath -Variables $variables | Should -Match '^.+\\Lenovo\\ThinInstaller\\ThinInstaller\.exe$'
    }
}

Describe 'Préchargement' {
    BeforeEach {
        Mock @m Assert-WingetAvailable { }
        Mock @m Get-WingetPackageVersion { '5.7.0' }
        Mock @m Save-RemoteFile { New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null; Set-Content -LiteralPath $Destination -Value 'x'; $Destination }
    }

    It 'utile seulement s''il y a un lien direct renseigné ou une dépendance .NET' {
        $context = New-TestContext -Folder $TestDrive
        Test-PrefetchUseful -UtilityKey 'dell' -Context $context | Should -BeTrue
        Test-PrefetchUseful -UtilityKey 'hp' -Context $context | Should -BeFalse
        Test-PrefetchUseful -UtilityKey 'lenovo' -Context $context | Should -BeFalse   # lien Thin Installer vide
        Test-PrefetchUseful -UtilityKey 'lenovo' -Context (New-TestContext -Folder $TestDrive -Config (New-LenovoConfig)) | Should -BeTrue
    }
    It 'Dell : version proposée par winget et runtime .NET résolus' {
        $result = Invoke-Prefetch -UtilityKey 'dell' -Context (New-TestContext -Folder $TestDrive)
        $result.ToolVersion | Should -Be '5.7.0'
        $result.DotNet.WingetId | Should -Be 'Microsoft.DotNet.DesktopRuntime.8'
        @($result.Errors).Count | Should -Be 0
    }
    It 'Lenovo : Thin Installer téléchargé dans le cache, puis retrouvé par l''étape' {
        $context = New-TestContext -Folder (Join-Path $TestDrive 'l1') -Config (New-LenovoConfig)
        $result = Invoke-Prefetch -UtilityKey 'lenovo' -Context $context
        @($result.Files).Count | Should -Be 1
        $item = $context.Config.Utilities.lenovo.Install[1]
        Get-PrefetchedItem -UtilityKey 'lenovo' -Item $item -Context $context | Should -Be (Join-Path $context.Paths.Cache 'lenovo\ThinInstallerSetup.exe')
    }
    It 'erreur de téléchargement : signalée, non bloquante' {
        Mock @m Save-RemoteFile { throw 'réseau indisponible' }
        $context = New-TestContext -Folder (Join-Path $TestDrive 'l2') -Config (New-LenovoConfig)
        $result = Invoke-Prefetch -UtilityKey 'lenovo' -Context $context
        @($result.Errors).Count | Should -Be 1
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line | Should -Match 'réseau indisponible'
    }
    It 'nom de fichier avec un chemin dans config.json : refusé' {
        { Get-PrefetchCachePath -UtilityKey 'x' -Item ([pscustomobject]@{ FileName = '..\evil.exe' }) -Context (New-TestContext -Folder $TestDrive) } | Should -Throw '*invalide*'
    }
}

Describe 'Étape 6 en mode réel — dépendance .NET puis utilitaire' {
    BeforeEach {
        Mock @m Assert-WingetAvailable { }
        Mock @m Get-WingetPackageVersion { '5.7.0' }
        Mock @m Install-WingetPackage { [pscustomobject]@{ RebootRequired = $false; AlreadyInstalled = $false } }
        Mock @m Get-DotNetDesktopRuntimeVersion { @() }
    }

    It 'runtime dans la plage déjà présent : rien installé pour .NET, DCU installé' {
        Mock @m Get-DotNetDesktopRuntimeVersion { @('8.0.20') }
        $results = Invoke-Vendor (New-TestContext -Folder $TestDrive -Mode Real) 'dell'
        @($results.Outcome) | Should -Be @('Succeeded', 'Succeeded')
        Should -Invoke @m Install-WingetPackage -Times 0 -ParameterFilter { $Id -like 'Microsoft.DotNet*' }
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Dell.CommandUpdate.Universal' }
    }
    It 'runtime absent : installé à la version maximale de la plage (DCU 5.7.0 → 8.0.25)' {
        $script:runtimeCalls = 0
        Mock @m Get-DotNetDesktopRuntimeVersion { $script:runtimeCalls++; if ($script:runtimeCalls -eq 1) { @() } else { @('8.0.25') } }
        $results = Invoke-Vendor (New-TestContext -Folder $TestDrive -Mode Real) 'dell'
        $results[0].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Microsoft.DotNet.DesktopRuntime.8' -and $Version -eq '8.0.25' }
    }
    It 'DCU 5.7.1 : runtime 10 sans borne haute, installé sans version imposée' {
        Mock @m Get-WingetPackageVersion { '5.7.1' }
        $script:runtimeCalls = 0
        Mock @m Get-DotNetDesktopRuntimeVersion { $script:runtimeCalls++; if ($script:runtimeCalls -eq 1) { @() } else { @('10.0.12') } }
        [void](Invoke-Vendor (New-TestContext -Folder $TestDrive -Mode Real) 'dell')
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Microsoft.DotNet.DesktopRuntime.10' -and -not $Version }
    }
    It 'runtime toujours hors plage après installation : échec, l''utilitaire est quand même tenté' {
        $results = Invoke-Vendor (New-TestContext -Folder $TestDrive -Mode Real) 'dell'
        $results[0].Outcome | Should -Be 'Failed'
        $results[0].Error | Should -Match 'hors de la plage'
        $results[1].Outcome | Should -Be 'Succeeded'
    }
    It 'runtime plus récent déjà présent : avertissement' {
        Mock @m Get-DotNetDesktopRuntimeVersion { @('8.0.20', '8.0.30') }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        [void](Invoke-Vendor $context 'dell')
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match 'plus récent.*8\.0\.30'
    }
    It 'Lenovo, lien vide : Vantage installé (msstore), Thin Installer en échec explicite' {
        $results = Invoke-Vendor (New-TestContext -Folder $TestDrive -Mode Real) 'lenovo'
        Should -Invoke @m Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq '9NR5B8GVVM13' -and $Source -eq 'msstore' }
        $results[1].Outcome | Should -Be 'Failed'
        $results[1].Error | Should -Match 'lien de téléchargement'
    }
    It 'Lenovo, fichier préchargé : réutilisé, signature Lenovo vérifiée, lancé avec ses arguments silencieux' {
        Mock @m Save-RemoteFile { throw 'ne doit pas être appelé' }
        Mock @m Assert-TrustedExecutable { }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
        $context = New-TestContext -Folder (Join-Path $TestDrive 'l3') -Mode Real -Config (New-LenovoConfig)
        $cached = Join-Path $context.Paths.Cache 'lenovo\ThinInstallerSetup.exe'
        New-Item -ItemType Directory -Path (Split-Path $cached) -Force | Out-Null
        Set-Content -LiteralPath $cached -Value 'x'
        $results = Invoke-Vendor $context 'lenovo'
        $results[1].Outcome | Should -Be 'Succeeded'
        Should -Invoke @m Assert-TrustedExecutable -Times 1 -ParameterFilter { $Path -eq $cached -and $ExpectedSigner -eq 'Lenovo' }
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -eq $cached -and $ArgumentList -eq '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
    }
    It 'signature refusée : rien n''est lancé' {
        Mock @m Save-RemoteFile { New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null; Set-Content -LiteralPath $Destination -Value 'x'; $Destination }
        Mock @m Assert-TrustedExecutable { throw 'signature non valide' }
        Mock @m Invoke-ExternalProcess { }
        $results = Invoke-Vendor (New-TestContext -Folder (Join-Path $TestDrive 'l4') -Mode Real -Config (New-LenovoConfig)) 'lenovo'
        $results[1].Outcome | Should -Be 'Failed'
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }
}

Describe 'Étape 11 en mode réel — mise à jour par l''utilitaire' {
    BeforeEach {
        Mock @m Assert-WingetAvailable { }
        Mock @m Get-WingetPackageVersion { '5.7.0' }
        Mock @m Install-WingetPackage { [pscustomobject]@{ RebootRequired = $false; AlreadyInstalled = $true } }
        Mock @m Get-DotNetDesktopRuntimeVersion { @('8.0.20') }
        Mock @m Find-InstalledExecutable { 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe' }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 1; RebootRequired = $true } }
    }
    It 'chemin développé, codes de succès et de redémarrage de config.json, redémarrage signalé' {
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $results = Invoke-Vendor $context 'dell' -Update
        $results[-1].Outcome | Should -Be 'Succeeded'
        $results[-1].RebootRequired | Should -BeTrue
        Should -Invoke @m Find-InstalledExecutable -Times 1 -ParameterFilter { $Path -eq 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe' }
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter {
            $ArgumentList -eq '/applyUpdates -reboot=disable' -and (@($SuccessExitCode) -join ',') -eq '0,500' -and (@($RebootExitCode) -join ',') -eq '1,5'
        }
    }
    It 'outil introuvable : échec explicite' {
        Mock @m Find-InstalledExecutable { throw 'Outil « HPImageAssistant.exe » introuvable' }
        $results = Invoke-Vendor (New-TestContext -Folder $TestDrive -Mode Real) 'hp' -Update
        $results[-1].Outcome | Should -Be 'Failed'
        $results[-1].Error | Should -Match 'introuvable'
    }
}
