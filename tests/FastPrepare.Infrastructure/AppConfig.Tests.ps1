BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Infrastructure

    function Get-ConfigError($Config) {
        try { [void](Assert-AppConfig -Config $Config); return $null } catch { return $_.Exception.Message }
    }
}

Describe 'Assert-AppConfig' {
    It 'config.json du dépôt : valide' {
        { Assert-AppConfig -Config (Get-TestConfig) } | Should -Not -Throw
    }

    It 'lien Thin Installer vide : avertissement, pas une erreur' {
        $warnings = Assert-AppConfig -Config (Get-TestConfig)
        $warnings | Should -Contain 'Utilities.lenovo.Install[1].Url : lien à renseigner avant la première installation réelle'
    }

    It 'ancienne configuration (sans ConfigVersion) : refus explicite' {
        $config = Get-TestConfig
        $config.PSObject.Properties.Remove('ConfigVersion')
        Get-ConfigError $config | Should -Match "ConfigVersion"
    }

    It 'version non prise en charge : refus' {
        $config = Get-TestConfig
        $config.ConfigVersion = 3
        Get-ConfigError $config | Should -Match 'ConfigVersion 3'
    }

    It 'clé obligatoire absente : erreur qui cite son chemin (<Path>)' -ForEach @(
        @{ Path = 'Connectivity.TestUrl'; Remove = { param($c) $c.Connectivity.PSObject.Properties.Remove('TestUrl') } }
        @{ Path = 'Utilities.dell.Update'; Remove = { param($c) $c.Utilities.dell.PSObject.Properties.Remove('Update') } }
        @{ Path = 'Office.Editions[1].ProductId'; Remove = { param($c) $c.Office.Editions[1].PSObject.Properties.Remove('ProductId') } }
        @{ Path = 'Power.ApplyOnBattery'; Remove = { param($c) $c.Power.PSObject.Properties.Remove('ApplyOnBattery') } }
    ) {
        $config = Get-TestConfig
        & $Remove $config
        Get-ConfigError $config | Should -Match ([regex]::Escape("$Path : absent"))
    }

    It 'liste toutes les erreurs en une fois' {
        $config = Get-TestConfig
        $config.Execution.DefaultMode = 'Turbo'
        $config.Power.MonitorTimeoutMinutes = -1
        $message = Get-ConfigError $config
        $message | Should -Match 'Execution.DefaultMode'
        $message | Should -Match 'Power.MonitorTimeoutMinutes'
    }

    It 'lien de téléchargement non https : erreur' {
        $config = Get-TestConfig
        $config.Utilities.lenovo.Install[1].Url = 'http://exemple.test/ThinInstaller.exe'
        Get-ConfigError $config | Should -Match 'https://'
    }

    It 'clé d''édition Office en double : erreur' {
        $config = Get-TestConfig
        $config.Office.Editions[1].Key = 'O365'
        Get-ConfigError $config | Should -Match 'en double'
    }

    It 'codes de redémarrage non entiers : erreur' {
        $config = Get-TestConfig
        $config.Utilities.dell.Update.RebootExitCodes = @('un')
        Get-ConfigError $config | Should -Match 'RebootExitCodes : entiers attendus'
    }

    It 'motif de constructeur invalide : erreur' {
        $config = Get-TestConfig
        $config.Utilities.hp.ManufacturerPattern = 'HP('
        Get-ConfigError $config | Should -Match 'expression régulière invalide'
    }
}

Describe 'Read-AppConfig' {
    It 'fichier absent : message clair' {
        { Read-AppConfig -Path (Join-Path $TestDrive 'absent.json') } | Should -Throw '*introuvable*'
    }
    It 'JSON invalide : message clair' {
        $path = Join-Path $TestDrive 'invalide.json'
        Set-Content -LiteralPath $path -Value '{ pas du json' -Encoding UTF8
        { Read-AppConfig -Path $path } | Should -Throw '*JSON valide*'
    }
}
