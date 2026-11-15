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
        $config.ConfigVersion = 5
        Get-ConfigError $config | Should -Match 'ConfigVersion 5'
    }

    It 'version 3 (avant l''outil indépendant du support) : refus avec la consigne de migration' {
        $config = Get-TestConfig
        $config.ConfigVersion = 3
        $message = Get-ConfigError $config
        $message | Should -Match "'Output'"
        $message | Should -Match 'Execution.WorkFolder'
    }

    It 'Output.Folder et Execution.WorkFolder : obligatoires' {
        $config = Get-TestConfig
        $config.PSObject.Properties.Remove('Output')
        $config.Execution.PSObject.Properties.Remove('WorkFolder')
        $message = Get-ConfigError $config
        $message | Should -Match 'Output : absent'
        $message | Should -Match 'Execution.WorkFolder : absent'
    }

    It 'Output.Folder : chemin relatif, absolu ou réseau accepté' -ForEach @(
        @{ Folder = 'logs' }
        @{ Folder = 'D:\Preparations\sortie' }
        @{ Folder = '\\serveur\partage\preparations' }
    ) {
        $config = Get-TestConfig
        $config.Output.Folder = $Folder
        { Assert-AppConfig -Config $config } | Should -Not -Throw
    }

    It 'Office.OdtFolder resté dans config.json : erreur explicite' {
        $config = Get-TestConfig
        $config.Office | Add-Member -NotePropertyName OdtFolder -NotePropertyValue 'C:\ODT'
        Get-ConfigError $config | Should -Match 'Office.OdtFolder : à retirer'
    }

    It 'Winget.OfflineBundle et ManualReminders : facultatifs' {
        $config = Get-TestConfig
        $config.Winget.PSObject.Properties.Remove('OfflineBundle')
        $config.PSObject.Properties.Remove('ManualReminders')
        { Assert-AppConfig -Config $config } | Should -Not -Throw
    }

    It 'version 2 (catalogue dans config.json) : refus avec la consigne de migration' {
        $config = Get-TestConfig
        $config.ConfigVersion = 2
        Get-ConfigError $config | Should -Match 'software.json'
    }

    It 'ancienne liste Software restée dans config.json : erreur explicite' {
        $config = Get-TestConfig
        $config | Add-Member -NotePropertyName Software -NotePropertyValue @()
        Get-ConfigError $config | Should -Match 'Software : la liste des logiciels est désormais'
    }

    It 'Winget.SourcePackage : facultatif, lien https et éditeur exigés s''il est présent' {
        $config = Get-TestConfig
        $config.Winget.PSObject.Properties.Remove('SourcePackage')
        { Assert-AppConfig -Config $config } | Should -Not -Throw
        $config = Get-TestConfig
        $config.Winget.SourcePackage.Url = 'http://cdn.exemple.test/source.msix'
        Get-ConfigError $config | Should -Match 'Winget.SourcePackage.Url : lien https'
        $config = Get-TestConfig
        $config.Winget.SourcePackage.ExpectedSigner = ''
        Get-ConfigError $config | Should -Match 'Winget.SourcePackage.ExpectedSigner'
    }

    It 'SoftwareCatalog absent : erreur' {
        $config = Get-TestConfig
        $config.PSObject.Properties.Remove('SoftwareCatalog')
        Get-ConfigError $config | Should -Match 'SoftwareCatalog : absent'
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

    It 'bloc NewLocalAccount absent : accepté (valeurs par défaut de l''outil)' {
        $config = Get-TestConfig
        $config.PSObject.Properties.Remove('NewLocalAccount')
        { Assert-AppConfig -Config $config } | Should -Not -Throw
    }

    It 'NewLocalAccount : options d''expiration contradictoires refusées' {
        $config = Get-TestConfig
        $config.NewLocalAccount.MustChangePassword = $true
        Get-ConfigError $config | Should -Match 'PasswordNeverExpires et MustChangePassword'
    }

    It 'NewLocalAccount : valeur non booléenne refusée' {
        $config = Get-TestConfig
        $config.NewLocalAccount.Administrator = 'oui'
        Get-ConfigError $config | Should -Match 'NewLocalAccount.Administrator : true ou false attendu'
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
