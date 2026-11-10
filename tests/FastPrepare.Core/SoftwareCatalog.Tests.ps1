<#
    Règles d'une entrée du catalogue des logiciels (itération 9). Liens et éditeurs fictifs.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core

    function New-Winget([hashtable]$Install = @{}, [string]$Label = '7-Zip', [string]$Id = '7-zip') {
        $values = @{ Type = 'winget'; Id = '7zip.7zip'; Source = 'winget'; Override = '' }
        foreach ($key in $Install.Keys) { $values[$key] = $Install[$key] }
        ConvertTo-SoftwareEntry -InputObject ([pscustomobject]@{ Id = $Id; Label = $Label; DefaultChecked = $false; Install = [pscustomobject]$values })
    }
    function New-Download([hashtable]$Install = @{}) {
        $values = @{ Type = 'download'; Url = 'https://telechargement.exemple.test/outil/setup.exe'; FileName = 'setup.exe'; Arguments = '/S'; Sha256 = ''; ExpectedSigner = 'Éditeur Exemple' }
        foreach ($key in $Install.Keys) { $values[$key] = $Install[$key] }
        ConvertTo-SoftwareEntry -InputObject ([pscustomobject]@{ Id = 'outil'; Label = 'Outil'; DefaultChecked = $true; Install = [pscustomobject]$values })
    }
}

Describe 'ConvertTo-SoftwareEntry' {
    It 'normalise : espaces retirés, empreinte en majuscules, seuls les champs du type conservés' {
        $entry = ConvertTo-SoftwareEntry -InputObject ([pscustomobject]@{
                Id = ' outil '; Label = ' Outil '; Install = [pscustomobject]@{ Type = 'Download'; Url = ' https://a.test/x.exe '; FileName = 'x.exe'; Sha256 = ('ab' * 32); ExpectedSigner = 'E'; Id = 'restes' }
            })
        $entry.Id | Should -Be 'outil'
        $entry.Label | Should -Be 'Outil'
        $entry.DefaultChecked | Should -BeFalse
        $entry.Install.Type | Should -Be 'download'
        $entry.Install.Url | Should -Be 'https://a.test/x.exe'
        $entry.Install.Sha256 | Should -Be ('AB' * 32)
        $entry.Install.Arguments | Should -Be ''
        $entry.Install.PSObject.Properties['Id'] | Should -BeNullOrEmpty
    }
    It 'source winget par défaut' {
        (ConvertTo-SoftwareEntry -InputObject ([pscustomobject]@{ Install = [pscustomobject]@{ Type = 'winget'; Id = 'x.y' } })).Install.Source | Should -Be 'winget'
    }
    It 'objet vide : entrée vide, sans erreur' {
        $entry = ConvertTo-SoftwareEntry -InputObject $null
        $entry.Label | Should -Be ''
        $entry.Install.Type | Should -Be ''
    }
}

Describe 'Get-SoftwareEntryError' {
    It 'entrées winget et lien direct correctes : aucun problème' {
        Get-SoftwareEntryError -Entry (New-Winget) | Should -BeNullOrEmpty
        Get-SoftwareEntryError -Entry (New-Winget @{ Source = 'msstore'; Id = '9NR5B8GVVM13' }) | Should -BeNullOrEmpty
        Get-SoftwareEntryError -Entry (New-Download) | Should -BeNullOrEmpty
        Get-SoftwareEntryError -Entry (New-Download @{ FileName = 'Outil Setup (x64).msi'; Sha256 = ('0F' * 32) }) | Should -BeNullOrEmpty
    }

    It 'winget refusé : <Why>' -ForEach @(
        @{ Why = 'identifiant vide'; Install = @{ Id = '' }; Pattern = 'Identifiant winget : vide' }
        @{ Why = 'espace dans l''identifiant'; Install = @{ Id = '7zip 7zip' }; Pattern = 'Identifiant winget : lettres' }
        @{ Why = 'source inconnue'; Install = @{ Source = 'choco' }; Pattern = 'Source winget' }
        @{ Why = 'guillemet dans les options'; Install = @{ Override = '/S /D="C:\x"' }; Pattern = 'guillemet interdit' }
    ) {
        (Get-SoftwareEntryError -Entry (New-Winget $Install)) -join ' | ' | Should -Match $Pattern
    }

    It 'lien direct refusé : <Why>' -ForEach @(
        @{ Why = 'http'; Install = @{ Url = 'http://exemple.test/a.exe' }; Pattern = 'Lien : lien https' }
        @{ Why = 'lien vide'; Install = @{ Url = '' }; Pattern = 'Lien : vide' }
        @{ Why = 'fichier .zip'; Install = @{ FileName = 'outil.zip' }; Pattern = 'Nom du fichier' }
        @{ Why = 'fichier avec dossier'; Install = @{ FileName = '..\setup.exe' }; Pattern = 'Nom du fichier' }
        @{ Why = 'éditeur absent'; Install = @{ ExpectedSigner = '' }; Pattern = 'Éditeur attendu : obligatoire' }
        @{ Why = 'empreinte trop courte'; Install = @{ Sha256 = 'ABC' }; Pattern = 'Empreinte SHA-256' }
    ) {
        (Get-SoftwareEntryError -Entry (New-Download $Install)) -join ' | ' | Should -Match $Pattern
    }

    It 'libellé vide ou trop long, identifiant interne invalide ou déjà pris' {
        (Get-SoftwareEntryError -Entry (New-Winget -Label '')) | Should -Contain 'Libellé : vide'
        (Get-SoftwareEntryError -Entry (New-Winget -Label ('x' * 81))) -join '' | Should -Match '81 caractères sur 80'
        (Get-SoftwareEntryError -Entry (New-Winget -Id '7 Zip')) -join '' | Should -Match 'minuscules'
        (Get-SoftwareEntryError -Entry (New-Winget) -ExistingId @('7-zip')) -join '' | Should -Match 'déjà utilisé'
    }

    It 'type inconnu' {
        $entry = ConvertTo-SoftwareEntry -InputObject ([pscustomobject]@{ Id = 'a'; Label = 'A'; Install = [pscustomobject]@{ Type = 'choco' } })
        (Get-SoftwareEntryError -Entry $entry) -join '' | Should -Match 'Type'
    }
}

Describe 'New-SoftwareId' {
    It '<Label> → <Expected>' -ForEach @(
        @{ Label = '7-Zip'; Expected = '7-zip' }
        @{ Label = 'Éditeur PDF (64 bits)'; Expected = 'editeur-pdf-64-bits' }
        @{ Label = '  !!  '; Expected = 'logiciel' }
    ) {
        New-SoftwareId -Label $Label | Should -Be $Expected
    }
    It 'rendu unique' {
        New-SoftwareId -Label '7-Zip' -ExistingId @('7-zip', '7-zip-2') | Should -Be '7-zip-3'
    }
}

Describe 'Format-SoftwareInstallCommand' {
    It 'winget, avec options' {
        Format-SoftwareInstallCommand -Entry (New-Winget @{ Override = '/S' }) | Should -Be 'winget install --id 7zip.7zip --source winget --silent --override "/S"'
    }
    It 'lien direct .exe et .msi' {
        Format-SoftwareInstallCommand -Entry (New-Download) | Should -Match 'setup.exe /S, signature « Éditeur Exemple » vérifiée$'
        Format-SoftwareInstallCommand -Entry (New-Download @{ FileName = 'outil.msi'; Arguments = ''; Sha256 = ('0F' * 32) }) | Should -Match 'msiexec /i outil.msi /qn /norestart, signature .* vérifiée, empreinte vérifiée'
    }
}

Describe 'Test-Selection — catalogue' {
    It 'logiciel coché absent du catalogue fourni : incohérence' {
        $selection = New-Selection
        $selection.ExtraSoftware.Ids = @('7-zip')
        $snapshot = New-TestSnapshot
        Test-Selection -Selection $selection -Config (Get-TestConfig) -Snapshot $snapshot | Should -Match "Logiciel inconnu"
        Test-Selection -Selection $selection -Config (Get-TestConfig) -Snapshot $snapshot -SoftwareCatalog @(New-Winget) | Should -BeNullOrEmpty
    }
}
