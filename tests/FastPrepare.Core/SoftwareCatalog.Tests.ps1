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

Describe 'Portée d''installation winget (DEC22)' {
    It 'normalisée en minuscules, affichée dans la commande' {
        $entry = New-Winget @{ Scope = 'Machine' }
        $entry.Install.Scope | Should -Be 'machine'
        Format-SoftwareInstallCommand -Entry $entry | Should -Be 'winget install --id 7zip.7zip --source winget --scope machine --silent'
    }
    It 'vide accepté (choix de winget, entrées antérieures)' {
        (New-Winget).Install.Scope | Should -Be ''
        Get-SoftwareEntryError -Entry (New-Winget) | Should -BeNullOrEmpty
        Format-SoftwareInstallCommand -Entry (New-Winget) | Should -Not -Match 'scope'
    }
    It 'valeur inconnue refusée' {
        (Get-SoftwareEntryError -Entry (New-Winget @{ Scope = 'tous' })) -join '' | Should -Match 'Portée'
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
        $selection.Catalog.Ids = @('7-zip')
        $snapshot = New-TestSnapshot
        Test-Selection -Selection $selection -Config (Get-TestConfig) -Snapshot $snapshot | Should -Match "Logiciel inconnu"
        Test-Selection -Selection $selection -Config (Get-TestConfig) -Snapshot $snapshot -SoftwareCatalog @(New-Winget) | Should -BeNullOrEmpty
    }
}

Describe 'Champs facultatifs d''une entrée (outils constructeurs, DEC25 et DEC26)' {
    BeforeAll {
        function New-Vendor([hashtable]$Change = @{}) {
            $values = @{
                Id = 'outil-marque'; Label = 'Outil de la marque'; DefaultChecked = $true; ManufacturerPattern = ' Marque|Autre '
                Install = [pscustomobject]@{ Type = 'winget'; Id = 'Marque.Outil'; Source = 'winget' }
                DotNet = @([pscustomobject]@{ ToolVersion = '5.7.0'; WingetId = 'Microsoft.DotNet.DesktopRuntime.8'; MinVersion = '8.0.8'; MaxVersion = '8.0.25' })
                Update = [pscustomobject]@{ FilePath = '%ProgramFiles%\Marque\outil-cli.exe'; Arguments = '/maj'; SuccessExitCodes = @(0, 500); RebootExitCodes = @(1) }
            }
            foreach ($key in $Change.Keys) { $values[$key] = $Change[$key] }
            ConvertTo-SoftwareEntry -InputObject ([pscustomobject]$values)
        }
    }

    It 'entrée simple : champs présents et vides (aucun accès à une propriété absente)' {
        $entry = New-Winget
        $entry.ManufacturerPattern | Should -Be ''
        @($entry.DotNet).Count | Should -Be 0
        $entry.Update | Should -BeNullOrEmpty
        @(Get-SoftwareEntryError -Entry $entry).Count | Should -Be 0
    }

    It 'entrée complète : normalisée et valide ; le libellé de la mise à jour vaut celui de l''entrée par défaut' {
        $entry = New-Vendor
        @(Get-SoftwareEntryError -Entry $entry).Count | Should -Be 0
        $entry.ManufacturerPattern | Should -Be 'Marque|Autre'
        $entry.DotNet[0].ToolVersion | Should -Be '5.7.0'
        $entry.Update.Label | Should -Be 'Outil de la marque'
        (@($entry.Update.SuccessExitCodes) -join ',') | Should -Be '0,500'
    }

    It 'refus : <Why>' -ForEach @(
        @{ Why = 'motif de constructeur invalide'; Change = @{ ManufacturerPattern = 'HP(' }; Pattern = 'Constructeur : expression régulière invalide' }
        @{ Why = 'version d''outil invalide'; Change = @{ DotNet = @([pscustomobject]@{ ToolVersion = 'x'; WingetId = 'A.B'; MinVersion = '8.0.8'; MaxVersion = '' }) }; Pattern = 'DotNet\[0\]\.ToolVersion' }
        @{ Why = 'runtime sans identifiant'; Change = @{ DotNet = @([pscustomobject]@{ ToolVersion = '1.0'; WingetId = ''; MinVersion = '8.0.8'; MaxVersion = '' }) }; Pattern = 'DotNet\[0\]\.WingetId' }
        @{ Why = 'version maximale invalide'; Change = @{ DotNet = @([pscustomobject]@{ ToolVersion = '1.0'; WingetId = 'A.B'; MinVersion = '8.0.8'; MaxVersion = 'dernière' }) }; Pattern = 'DotNet\[0\]\.MaxVersion' }
        @{ Why = 'dépendance .NET sur un lien direct'; Change = @{ Install = [pscustomobject]@{ Type = 'download'; Url = 'https://telechargement.exemple.test/o.exe'; FileName = 'o.exe'; ExpectedSigner = 'Marque' } }; Pattern = 'DotNet : réservé aux paquets winget' }
        @{ Why = 'mise à jour sans exécutable'; Change = @{ Update = [pscustomobject]@{ FilePath = ''; Arguments = ''; SuccessExitCodes = @(0) } }; Pattern = 'Update\.FilePath : vide' }
        @{ Why = 'mise à jour sans code de succès'; Change = @{ Update = [pscustomobject]@{ FilePath = 'o.exe'; Arguments = '' } }; Pattern = 'Update\.SuccessExitCodes : au moins un' }
        @{ Why = 'codes de redémarrage non entiers'; Change = @{ Update = [pscustomobject]@{ FilePath = 'o.exe'; Arguments = ''; SuccessExitCodes = @(0); RebootExitCodes = @('un') } }; Pattern = 'Update\.RebootExitCodes : entiers attendus' }
    ) {
        (Get-SoftwareEntryError -Entry (New-Vendor -Change $Change)) -join "`n" | Should -Match $Pattern
    }

    It 'forme écrite dans software.json : champs facultatifs vides omis, les autres conservés' {
        @((ConvertTo-SoftwareDocumentEntry -Entry (New-Winget)).PSObject.Properties.Name) | Should -Be @('Id', 'Label', 'DefaultChecked', 'Install')
        @((ConvertTo-SoftwareDocumentEntry -Entry (New-Vendor)).PSObject.Properties.Name) | Should -Be @('Id', 'Label', 'DefaultChecked', 'ManufacturerPattern', 'Install', 'DotNet', 'Update')
    }
}
