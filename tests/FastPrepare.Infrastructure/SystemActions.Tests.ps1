<#
    Adaptateurs qui modifient le poste : jamais exécutés pour de vrai dans les tests.
    Les commandes Windows sont remplacées par des simulacres (Mock) ; on vérifie ce qui serait appelé.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Infrastructure
}

Describe 'winget' {
    It 'arguments d''installation : id exact, source, silencieux, accords acceptés, override entre guillemets' {
        $arguments = Get-WingetInstallArgument -Id 'Adobe.Acrobat.Reader.64-bit' -Source 'winget' -Override '-sfx_nu /sAll /rs /msi'
        $arguments | Should -Be 'install --id Adobe.Acrobat.Reader.64-bit --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity --override "-sfx_nu /sAll /rs /msi"'
    }
    It 'refuse un identifiant ou un override qui casserait la ligne de commande' {
        { Get-WingetInstallArgument -Id 'A B' -Source 'winget' } | Should -Throw
        { Get-WingetInstallArgument -Id 'A' -Source 'winget' -Override 'x" & calc' } | Should -Throw
    }
    It '« déjà installé » est un succès' {
        Mock -ModuleName FastPrepare.Infrastructure Get-Command { [pscustomobject]@{ Source = 'C:\winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
        Mock -ModuleName FastPrepare.Infrastructure Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0x8A150061; RebootRequired = $false } }
        $result = Install-WingetPackage -Id 'X.Y' -Source 'winget'
        $result.AlreadyInstalled | Should -BeTrue
        Should -Invoke -ModuleName FastPrepare.Infrastructure Invoke-ExternalProcess -Times 1 -ParameterFilter { $SuccessExitCode -contains 0x8A150061 }
    }
}

Describe 'Assert-WingetAvailable (contraintes du cahier)' {
    It 'déjà présent : rien n''est installé' {
        Mock -ModuleName FastPrepare.Infrastructure Test-Winget { $true }
        Mock -ModuleName FastPrepare.Infrastructure Add-AppxPackage { }
        Assert-WingetAvailable -FamilyName 'F' -OfflineBundle 'C:\absent.msixbundle'
        Should -Invoke -ModuleName FastPrepare.Infrastructure Add-AppxPackage -Times 0
    }
    It 'absent : réenregistrement par nom de famille' {
        $script:wingetCalls = 0
        Mock -ModuleName FastPrepare.Infrastructure Test-Winget { $script:wingetCalls++; $script:wingetCalls -gt 1 }
        Mock -ModuleName FastPrepare.Infrastructure Add-AppxPackage { }
        Assert-WingetAvailable -FamilyName 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -OfflineBundle 'C:\absent.msixbundle'
        Should -Invoke -ModuleName FastPrepare.Infrastructure Add-AppxPackage -Times 1 -ParameterFilter { $RegisterByFamilyName -and $MainPackage -eq 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' }
    }
    It 'réenregistrement sans effet et paquet hors ligne absent : erreur explicite' {
        Mock -ModuleName FastPrepare.Infrastructure Test-Winget { $false }
        Mock -ModuleName FastPrepare.Infrastructure Add-AppxPackage { }
        { Assert-WingetAvailable -FamilyName 'F' -OfflineBundle (Join-Path $TestDrive 'absent.msixbundle') } | Should -Throw '*paquet hors ligne absent*'
    }
    It 'réenregistrement sans effet : installation du paquet de la clé avec ses dépendances' {
        $folder = Join-Path $TestDrive 'packages'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $bundle = Join-Path $folder 'Microsoft.DesktopAppInstaller.msixbundle'
        Set-Content -LiteralPath $bundle -Value 'x'
        Set-Content -LiteralPath (Join-Path $folder 'Microsoft.VCLibs.x64.appx') -Value 'x'
        $script:wingetCalls = 0
        Mock -ModuleName FastPrepare.Infrastructure Test-Winget { $script:wingetCalls++; $script:wingetCalls -gt 2 }
        Mock -ModuleName FastPrepare.Infrastructure Add-AppxPackage { }
        Assert-WingetAvailable -FamilyName 'F' -OfflineBundle $bundle
        Should -Invoke -ModuleName FastPrepare.Infrastructure Add-AppxPackage -Times 1 -ParameterFilter { $Path -eq $bundle -and @($DependencyPath).Count -eq 1 }
    }
}

Describe 'Alimentation' {
    It 'réglages secteur et batterie' {
        @(Get-PowerTimeoutSetting -MonitorMinutes 5 -StandbyMinutes 15 -IncludeBattery).Name | Should -Be @('monitor-timeout-ac', 'monitor-timeout-dc', 'standby-timeout-ac', 'standby-timeout-dc')
    }
    It 'secteur seulement' {
        @(Get-PowerTimeoutSetting -MonitorMinutes 5 -StandbyMinutes 15).Name | Should -Be @('monitor-timeout-ac', 'standby-timeout-ac')
    }
    It 'une commande powercfg /change par réglage, par son chemin absolu' {
        Mock -ModuleName FastPrepare.Infrastructure Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
        Set-PowerTimeout -MonitorMinutes 5 -StandbyMinutes 15 -IncludeBattery
        Should -Invoke -ModuleName FastPrepare.Infrastructure Invoke-ExternalProcess -Times 4
        Should -Invoke -ModuleName FastPrepare.Infrastructure Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -like '*\System32\powercfg.exe' -and $ArgumentList -eq '/change standby-timeout-dc 15' }
    }
}

Describe 'IPv6' {
    It 'déjà désactivé : aucune modification' {
        Mock -ModuleName FastPrepare.Infrastructure Get-NetAdapterBinding { [pscustomobject]@{ Enabled = $false } }
        Mock -ModuleName FastPrepare.Infrastructure Disable-NetAdapterBinding { }
        (Disable-AdapterIpv6 -Name 'Ethernet').Changed | Should -BeFalse
        Should -Invoke -ModuleName FastPrepare.Infrastructure Disable-NetAdapterBinding -Times 0
    }
    It 'actif : désactivé puis vérifié' {
        $script:bindingCalls = 0
        Mock -ModuleName FastPrepare.Infrastructure Get-NetAdapterBinding { $script:bindingCalls++; [pscustomobject]@{ Enabled = ($script:bindingCalls -eq 1) } }
        Mock -ModuleName FastPrepare.Infrastructure Disable-NetAdapterBinding { }
        (Disable-AdapterIpv6 -Name 'Ethernet').Changed | Should -BeTrue
        Should -Invoke -ModuleName FastPrepare.Infrastructure Disable-NetAdapterBinding -Times 1 -ParameterFilter { $Name -eq 'Ethernet' -and $ComponentID -eq 'ms_tcpip6' }
    }
    It 'toujours actif après désactivation : erreur' {
        Mock -ModuleName FastPrepare.Infrastructure Get-NetAdapterBinding { [pscustomobject]@{ Enabled = $true } }
        Mock -ModuleName FastPrepare.Infrastructure Disable-NetAdapterBinding { }
        { Disable-AdapterIpv6 -Name 'Ethernet' } | Should -Throw '*toujours actif*'
    }
}

Describe 'Nom d''hôte' {
    It 'même nom : rien à faire, pas de redémarrage' {
        Mock -ModuleName FastPrepare.Infrastructure Rename-Computer { }
        $result = Rename-LocalComputer -NewName $env:COMPUTERNAME
        $result.Changed | Should -BeFalse
        Should -Invoke -ModuleName FastPrepare.Infrastructure Rename-Computer -Times 0
    }
    It 'nouveau nom : Rename-Computer sans redémarrage automatique, redémarrage signalé' {
        Mock -ModuleName FastPrepare.Infrastructure Rename-Computer { }
        $result = Rename-LocalComputer -NewName 'PC-NOUVEAU'
        $result.RebootRequired | Should -BeTrue
        Should -Invoke -ModuleName FastPrepare.Infrastructure Rename-Computer -Times 1 -ParameterFilter { $NewName -eq 'PC-NOUVEAU' -and -not $Restart }
    }
}
