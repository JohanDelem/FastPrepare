BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
    $m = @{ ModuleName = 'FastPrepare.Infrastructure' }
}

Describe 'Version proposée par winget' {
    It 'sortie en anglais' {
        ConvertFrom-WingetShowOutput -Output "Found Dell Command | Update [Dell.CommandUpdate.Universal]`r`nVersion: 5.7.0`r`nPublisher: Dell" | Should -Be '5.7.0'
    }
    It 'sortie en français (espace avant les deux-points)' {
        ConvertFrom-WingetShowOutput -Output "Trouvé Dell Command | Update`r`nVersion : 5.7.1`r`nÉditeur : Dell" | Should -Be '5.7.1'
    }
    It 'ne confond pas avec « Release Notes Version » ou une ligne indentée de sous-champ' {
        ConvertFrom-WingetShowOutput -Output "Moniker: dcu`nVersion: 5.7.0`nRelease Notes Url: https://x" | Should -Be '5.7.0'
    }
    It 'version absente : erreur' {
        { ConvertFrom-WingetShowOutput -Output 'Aucun paquet trouvé' } | Should -Throw '*Version introuvable*'
    }
    It 'winget show appelé avec l''identifiant exact et la source' {
        Mock @m Get-Command { [pscustomobject]@{ Source = 'C:\winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; Output = 'Version: 5.7.0' } }
        Get-WingetPackageVersion -Id 'Dell.CommandUpdate.Universal' -Source 'winget' | Should -Be '5.7.0'
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $ArgumentList -like 'show --id Dell.CommandUpdate.Universal --exact --source winget*' -and $CaptureOutput }
    }
    It 'installation d''une version précise : --version, refus d''une version mal formée' {
        Get-WingetInstallArgument -Id 'Microsoft.DotNet.DesktopRuntime.8' -Source 'winget' -Version '8.0.25' | Should -Match ' --version 8\.0\.25$'
        { Get-WingetInstallArgument -Id 'X' -Source 'winget' -Version '8.0; calc' } | Should -Throw
    }
}

Describe 'Runtimes .NET Desktop installés' {
    It 'lit les versions dans le registre (x64 et x86, sans doublon)' {
        Mock @m Get-ItemProperty { [pscustomobject]@{ '8.0.25' = 1; '10.0.8' = 1; PSPath = 'x'; PSProvider = 'y' } }
        Get-DotNetDesktopRuntimeVersion | Should -Be @('10.0.8', '8.0.25')
    }
    It 'aucun runtime : liste vide' {
        Mock @m Get-ItemProperty { $null }
        @(Get-DotNetDesktopRuntimeVersion).Count | Should -Be 0
    }
}

Describe 'Find-InstalledExecutable (fichiers réels dans $TestDrive)' {
    BeforeAll {
        $root = Join-Path $TestDrive 'Programmes'
        New-Item -ItemType Directory -Path (Join-Path $root 'HP\HPIA\bin') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'HP\HPIA\bin\HPImageAssistant.exe') -Value 'x'
        New-Item -ItemType Directory -Path (Join-Path $root 'a\b\c\d') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'a\b\c\d\Profond.exe') -Value 'x'
    }
    It 'chemin absolu existant : renvoyé tel quel' {
        $path = Join-Path $root 'HP\HPIA\bin\HPImageAssistant.exe'
        Find-InstalledExecutable -Path $path | Should -Be $path
    }
    It 'chemin absolu absent : erreur' {
        { Find-InstalledExecutable -Path (Join-Path $root 'absent.exe') } | Should -Throw '*introuvable*'
    }
    It 'nom seul : trouvé dans les dossiers d''installation (trois niveaux)' {
        Find-InstalledExecutable -Path 'HPImageAssistant.exe' -SearchRoot @($root) | Should -Be (Join-Path $root 'HP\HPIA\bin\HPImageAssistant.exe')
    }
    It 'nom seul plus profond que trois niveaux : introuvable' {
        { Find-InstalledExecutable -Path 'Profond.exe' -SearchRoot @($root) } | Should -Throw '*introuvable*'
    }
    It 'nom seul présent dans le PATH' {
        Find-InstalledExecutable -Path 'cmd.exe' -SearchRoot @() | Should -Match 'cmd\.exe$'
    }
}
