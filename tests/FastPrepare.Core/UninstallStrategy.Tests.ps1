BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
    $entries = Get-Content (Join-Path $PSScriptRoot '..\Fixtures\registry-uninstall-entries.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    function Get-Entry([string]$Case) { $entries | Where-Object Case -EQ $Case }
}

Describe 'Resolve-UninstallStrategy (tableau « Désinstallation silencieuse »)' {
    It 'QuietUninstallString fournie : utilisée telle quelle' {
        $s = Resolve-UninstallStrategy -Entry (Get-Entry 'quiet')
        $s.Silent | Should -BeTrue
        $s.Method | Should -Be 'QuietUninstallString'
        $s.Command | Should -Be '"C:\A\uninst.exe" /quiet'
    }
    It 'MSI : GUID pris dans le nom de la clé' {
        $s = Resolve-UninstallStrategy -Entry (Get-Entry 'msi-key')
        $s.Method | Should -Be 'MSI'
        $s.Command | Should -Be 'msiexec.exe /x {11111111-2222-3333-4444-555555555555} /qn /norestart'
    }
    It 'MSI : GUID pris dans la chaîne /I{GUID}' {
        (Resolve-UninstallStrategy -Entry (Get-Entry 'msi-string')).Command | Should -Be 'msiexec.exe /x {AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE} /qn /norestart'
    }
    It 'Inno Setup reconnu au nom unins000.exe' {
        $probe = [pscustomobject]@{ Path = 'C:\D\unins000.exe'; Exists = $true; IsNsis = $false }
        $s = Resolve-UninstallStrategy -Entry (Get-Entry 'inno') -ExecutableProbe $probe
        $s.Method | Should -Be 'Inno Setup'
        $s.Command | Should -Be '"C:\D\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
    }
    It 'NSIS reconnu par la sonde' {
        $probe = [pscustomobject]@{ Path = 'C:\E\uninstall.exe'; Exists = $true; IsNsis = $true }
        $s = Resolve-UninstallStrategy -Entry (Get-Entry 'nsis') -ExecutableProbe $probe
        $s.Method | Should -Be 'NSIS'
        $s.Command | Should -Be '"C:\E\uninstall.exe" /S'
    }
    It 'exécutable absent du disque : assistant' {
        $probe = [pscustomobject]@{ Path = 'C:\D\unins000.exe'; Exists = $false; IsNsis = $false }
        (Resolve-UninstallStrategy -Entry (Get-Entry 'inno') -ExecutableProbe $probe).Method | Should -Be 'Assistant'
    }
    It 'aucun cas reconnu : assistant, non silencieux' {
        $s = Resolve-UninstallStrategy -Entry (Get-Entry 'wizard')
        $s.Silent | Should -BeFalse
        $s.Method | Should -Be 'Assistant'
        $s.Command | Should -Be 'C:\F\setup.exe /remove'
    }
    It 'aucune commande' {
        (Resolve-UninstallStrategy -Entry (Get-Entry 'none')).Method | Should -Be 'Aucune commande'
    }
}

Describe 'Get-UninstallProbeTarget' {
    It 'aucun examen de fichier quand QuietUninstallString ou MSI suffit' {
        Get-UninstallProbeTarget -Entry (Get-Entry 'quiet') | Should -BeNullOrEmpty
        Get-UninstallProbeTarget -Entry (Get-Entry 'msi-key') | Should -BeNullOrEmpty
    }
    It 'extrait l''exécutable entre guillemets ou jusqu''au .exe' {
        Get-UninstallProbeTarget -Entry (Get-Entry 'nsis') | Should -Be 'C:\E\uninstall.exe'
        Get-UninstallProbeTarget -Entry (Get-Entry 'wizard') | Should -Be 'C:\F\setup.exe'
    }
}

Describe 'Get-UninstallOrder (ordre d''exécution n° 5)' {
    It 'silencieux d''abord, assistants en dernier, alphabétique dans chaque groupe' {
        $software = @(
            [pscustomobject]@{ Name = 'Zeta'; Silent = $false }
            [pscustomobject]@{ Name = 'Beta'; Silent = $true }
            [pscustomobject]@{ Name = 'Alpha'; Silent = $false }
            [pscustomobject]@{ Name = 'Gamma'; Silent = $true }
        )
        (Get-UninstallOrder -Software $software).Name | Should -Be @('Beta', 'Gamma', 'Alpha', 'Zeta')
    }
    It 'liste vide' {
        @(Get-UninstallOrder -Software @()).Count | Should -Be 0
    }
}
