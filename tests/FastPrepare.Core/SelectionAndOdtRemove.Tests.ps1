BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
    $config = Get-TestConfig
    $snapshot = New-TestSnapshot
    $catalog = @(Get-TestCatalogEntry)
}

Describe 'Test-Selection (cohérence avant construction du plan)' {
    It 'sélection vide : cohérente' {
        @(Test-Selection -Selection (New-Selection) -Config $config -Snapshot $snapshot).Count | Should -Be 0
    }
    It 'détecte <Why>' -ForEach @(
        @{ Why = 'nom d''hôte invalide'; Change = { param($s) $s.HostName.Enabled = $true; $s.HostName.Name = '123' }; Pattern = "Nom d'hôte" }
        @{ Why = 'dossier OneDrive sans OneDrive'; Change = { param($s) $s.MicrosoftApps.OneDriveFolder = $true }; Pattern = 'OneDrive' }
        @{ Why = 'compte non supprimable'; Change = { param($s) $s.LocalAccounts.Items = @([pscustomobject]@{ Name = 'Administrateur'; Sid = 'S-1-5-21-1-2-3-500' }) }; Pattern = 'Administrateur' }
        @{ Why = 'outil d''un autre constructeur'; Change = { param($s) $s.Catalog.Ids = @('hp-image-assistant') }; Pattern = 'HP Image Assistant » est réservé à un autre constructeur que celui du poste \(Dell Inc\.\)' }
        @{ Why = 'pilotes et BIOS sans outil constructeur coché'; Change = { param($s) $s.Updates.Drivers = $true }; Pattern = 'sans outil constructeur' }
        @{ Why = 'pilotes et BIOS avec un outil sans commande Update'; Change = { param($s) $s.Catalog.Ids = @('adobe-reader'); $s.Updates.Drivers = $true }; Pattern = 'sans outil constructeur' }
        @{ Why = 'édition inconnue'; Change = { param($s) $s.Office.EditionKey = 'XP' }; Pattern = 'XP' }
        @{ Why = 'sans Teams pour LTSC'; Change = { param($s) $s.Office.EditionKey = 'LTSC2024'; $s.Office.WithoutTeams = $true }; Pattern = 'sans Teams' }
        @{ Why = 'logiciel inconnu'; Change = { param($s) $s.Catalog.Ids = @('inconnu') }; Pattern = "Logiciel inconnu du catalogue : 'inconnu'" }
    ) {
        $selection = New-Selection
        & $Change $selection
        (Test-Selection -Selection $selection -Config $config -Snapshot $snapshot -SoftwareCatalog $catalog) -join "`n" | Should -Match $Pattern
    }
    It 'outil du constructeur du poste, avec sa mise à jour : cohérent' {
        $selection = New-Selection
        $selection.Catalog.Ids = @('dell-command-update', 'adobe-reader')
        $selection.Updates.Drivers = $true
        @(Test-Selection -Selection $selection -Config $config -Snapshot $snapshot -SoftwareCatalog $catalog).Count | Should -Be 0
    }
    It 'constructeur non détecté : tout outil constructeur est refusé' {
        $selection = New-Selection
        $selection.Catalog.Ids = @('dell-command-update')
        (Test-Selection -Selection $selection -Config $config -Snapshot (New-TestSnapshot -Manufacturer '') -SoftwareCatalog $catalog) -join "`n" | Should -Match 'constructeur non détecté'
    }
}

Describe 'New-OdtRemoveXml (section 3)' {
    It 'Click-to-Run et MSI : Remove All + RemoveMSI, affichage silencieux' {
        $xml = [xml](New-OdtRemoveXml -RemoveClickToRun -RemoveMsi)
        $xml.Configuration.Remove.All | Should -Be 'TRUE'
        $xml.Configuration.SelectSingleNode('RemoveMSI') | Should -Not -BeNullOrEmpty
        $xml.Configuration.Display.Level | Should -Be 'None'
    }
    It 'MSI seul : pas de Remove All' {
        $xml = [xml](New-OdtRemoveXml -RemoveMsi)
        $xml.Configuration.SelectSingleNode('Remove') | Should -BeNullOrEmpty
    }
    It 'rien à supprimer : erreur' {
        { New-OdtRemoveXml } | Should -Throw
    }
}
