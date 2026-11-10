<#
    Modification et test du catalogue (itération 9). Adaptateurs simulés : aucun accès réseau,
    et surtout aucun téléchargement ni aucune installation pendant un test.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }

    function New-FormEntry([string]$Id = '7-zip', [string]$Label = '7-Zip', [hashtable]$Install = @{ Type = 'winget'; Id = '7zip.7zip'; Source = 'winget' }) {
        [pscustomobject]@{ Id = $Id; Label = $Label; DefaultChecked = $false; Install = [pscustomobject]$Install }
    }
    $download = @{ Type = 'download'; Url = 'https://telechargement.exemple.test/outil.exe'; FileName = 'outil.exe'; Arguments = '/S'; ExpectedSigner = 'Éditeur Exemple' }
}

Describe 'Set-SoftwareCatalogEntry / Remove-SoftwareCatalogEntry' {
    BeforeEach {
        # Un dossier par test : chaque test part du catalogue du dépôt, sans fichier écrit.
        $folder = New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $context = New-TestContext -Folder $folder.FullName
    }

    It 'ajoute en fin de catalogue, écrit le fichier et met le contexte à jour' {
        [void](Set-SoftwareCatalogEntry -Context $context -Entry (New-FormEntry))
        @($context.SoftwareCatalog).Id | Should -Be @('adobe-reader', '7-zip')
        @((Read-SoftwareCatalog -Path $context.Paths.SoftwareCatalog).Entries).Id | Should -Be @('adobe-reader', '7-zip')
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match '7-Zip ajouté'
    }

    It 'remplace à la même place, y compris avec un nouvel identifiant' {
        [void](Set-SoftwareCatalogEntry -Context $context -Entry (New-FormEntry -Id 'lecteur-pdf' -Label 'Lecteur PDF' -Install @{ Type = 'winget'; Id = 'Adobe.Acrobat.Reader.64-bit'; Source = 'winget' }) -PreviousId 'adobe-reader')
        @($context.SoftwareCatalog).Id | Should -Be @('lecteur-pdf')
    }

    It 'entrée invalide ou identifiant déjà pris : refus, rien n''est écrit' {
        { Set-SoftwareCatalogEntry -Context $context -Entry (New-FormEntry -Install @{ Type = 'winget'; Id = 'a b'; Source = 'winget' }) } | Should -Throw '*Identifiant winget*'
        { Set-SoftwareCatalogEntry -Context $context -Entry (New-FormEntry -Id 'adobe-reader') } | Should -Throw '*déjà utilisé*'
        Test-Path -LiteralPath $context.Paths.SoftwareCatalog | Should -BeFalse
        @($context.SoftwareCatalog).Count | Should -Be 1
    }

    It 'retire une entrée ; identifiant inconnu refusé' {
        Remove-SoftwareCatalogEntry -Context $context -Id 'adobe-reader'
        @($context.SoftwareCatalog).Count | Should -Be 0
        { Remove-SoftwareCatalogEntry -Context $context -Id 'inconnu' } | Should -Throw '*inconnu*'
    }
}

Describe 'Test-SoftwareCatalogEntry (sans téléchargement ni installation)' {
    BeforeEach {
        $context = New-TestContext -Folder $TestDrive
        Mock @m Test-Winget { $true }
        Mock @m Get-WingetPackageInfo { [pscustomobject]@{ Name = '7-Zip'; Version = '24.09' } }
        Mock @m Test-RemoteFile { [pscustomobject]@{ StatusCode = 200; ContentType = 'application/octet-stream'; ContentLength = 2MB; FinalUrl = $Url } }
        Mock @m Install-WingetPackage { throw 'interdit pendant un test' }
        Mock @m Save-RemoteFile { throw 'interdit pendant un test' }
        Mock @m Invoke-ExternalProcess { throw 'interdit pendant un test' }
        Mock @m Assert-WingetAvailable { throw 'interdit pendant un test' }
    }
    AfterEach {
        Should -Invoke @m Install-WingetPackage -Times 0
        Should -Invoke @m Save-RemoteFile -Times 0
        Should -Invoke @m Invoke-ExternalProcess -Times 0
        Should -Invoke @m Assert-WingetAvailable -Times 0
    }

    It 'winget : paquet trouvé, nom et version affichés, test journalisé' {
        $result = Test-SoftwareCatalogEntry -Entry (New-FormEntry) -Context $context
        $result.Succeeded | Should -BeTrue
        $result.Lines[0].Text | Should -Be 'Paquet trouvé : 7-Zip, version 24.09 (source winget)'
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match 'Test du logiciel 7-Zip \(sans téléchargement ni installation\) : réussi'
    }

    It 'portée « machine » : installateur affiché ; aucun installateur pour la portée → échec' {
        Mock @m Get-WingetPackageInfo { [pscustomobject]@{ Name = 'Microsoft Visual Studio Code'; Version = '1.143.1'; InstallerFound = $true; InstallerFile = 'VSCodeSetup-x64-1.143.1.exe' } }
        $result = Test-SoftwareCatalogEntry -Entry (New-FormEntry -Install @{ Type = 'winget'; Id = 'Microsoft.VisualStudioCode'; Source = 'winget'; Scope = 'machine' }) -Context $context
        $result.Succeeded | Should -BeTrue
        ($result.Lines.Text -join ' | ') | Should -Match 'Installateur pour tous les utilisateurs \(machine\) : VSCodeSetup-x64-1.143.1.exe'
        Should -Invoke @m Get-WingetPackageInfo -Times 1 -ParameterFilter { $Scope -eq 'machine' }

        Mock @m Get-WingetPackageInfo { [pscustomobject]@{ Name = '7-Zip'; Version = '26.06'; InstallerFound = $false; InstallerFile = '' } }
        $result = Test-SoftwareCatalogEntry -Entry (New-FormEntry -Install @{ Type = 'winget'; Id = '7zip.7zip'; Source = 'winget'; Scope = 'user' }) -Context $context
        $result.Succeeded | Should -BeFalse
        ($result.Lines | Where-Object Level -EQ 'ERREUR').Text | Should -Match 'aucun installateur pour le compte qui lance'
    }

    It 'portée non précisée : avertissement' {
        $result = Test-SoftwareCatalogEntry -Entry (New-FormEntry) -Context $context
        $result.Succeeded | Should -BeTrue
        ($result.Lines | Where-Object Level -EQ 'ATTN').Text | Should -Match 'Portée non précisée'
    }

    It 'winget : paquet introuvable → échec avec le motif' {
        Mock @m Get-WingetPackageInfo { throw 'paquet « x.y » introuvable dans la source « winget »' }
        $result = Test-SoftwareCatalogEntry -Entry (New-FormEntry -Install @{ Type = 'winget'; Id = 'x.y'; Source = 'winget' }) -Context $context
        $result.Succeeded | Should -BeFalse
        ($result.Lines | Where-Object Level -EQ 'ERREUR').Text | Should -Match 'introuvable'
    }

    It 'winget absent du poste : échec explicite' {
        Mock @m Test-Winget { $false }
        (Test-SoftwareCatalogEntry -Entry (New-FormEntry) -Context $context).Lines[0].Text | Should -Match 'winget indisponible'
    }

    It 'saisie invalide : aucune vérification en ligne' {
        $result = Test-SoftwareCatalogEntry -Entry (New-FormEntry -Label '') -Context $context
        $result.Succeeded | Should -BeFalse
        Should -Invoke @m Get-WingetPackageInfo -Times 0
    }

    It 'lien direct valide : taille annoncée, rappel de ce qui ne peut être vérifié qu''à l''installation' {
        $result = Test-SoftwareCatalogEntry -Entry (New-FormEntry -Id 'outil' -Label 'Outil' -Install $download) -Context $context
        $result.Succeeded | Should -BeTrue
        ($result.Lines | Where-Object Level -EQ 'OK').Text | Should -Match 'fichier de 2[,.]0 Mo'
        ($result.Lines | Where-Object Level -EQ 'ATTN').Text | Should -Match 'Signature « Éditeur Exemple »'
    }

    It 'lien direct vers une page web : échec' {
        Mock @m Test-RemoteFile { [pscustomobject]@{ StatusCode = 200; ContentType = 'text/html'; ContentLength = 5000; FinalUrl = $Url } }
        $result = Test-SoftwareCatalogEntry -Entry (New-FormEntry -Id 'outil' -Label 'Outil' -Install $download) -Context $context
        $result.Succeeded | Should -BeFalse
        ($result.Lines | Where-Object Level -EQ 'ERREUR').Text | Should -Match 'page web'
    }

    It 'lien direct : erreur 404 ou redirection hors https' {
        Mock @m Test-RemoteFile { [pscustomobject]@{ StatusCode = 404; ContentType = 'text/plain'; ContentLength = 0; FinalUrl = $Url } }
        (Test-SoftwareCatalogEntry -Entry (New-FormEntry -Id 'outil' -Label 'Outil' -Install $download) -Context $context).Lines[0].Text | Should -Match '404'
        Mock @m Test-RemoteFile { [pscustomobject]@{ StatusCode = 200; ContentType = 'application/octet-stream'; ContentLength = 1; FinalUrl = 'http://miroir.test/outil.exe' } }
        (Test-SoftwareCatalogEntry -Entry (New-FormEntry -Id 'outil' -Label 'Outil' -Install $download) -Context $context).Lines[0].Text | Should -Match 'hors https'
    }
}

Describe 'Installation d''un logiciel par lien direct (mode réel, simulacres)' {
    BeforeEach {
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $context.SoftwareCatalog = @(
            ConvertTo-SoftwareEntry -InputObject (New-FormEntry -Id 'outil' -Label 'Outil' -Install $download)
            ConvertTo-SoftwareEntry -InputObject (New-FormEntry -Id 'outil-msi' -Label 'Outil MSI' -Install @{ Type = 'download'; Url = 'https://telechargement.exemple.test/outil.msi'; FileName = 'outil.msi'; Arguments = 'ALLUSERS=1'; ExpectedSigner = 'Éditeur Exemple' })
        )
        Mock @m Save-RemoteFile { $Destination }
        Mock @m Assert-TrustedExecutable { }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
    }

    It '.exe : téléchargé dans le cache, signature vérifiée, lancé avec ses arguments ; .msi par msiexec' {
        $selection = New-Selection
        $selection.ExtraSoftware.Ids = @('outil', 'outil-msi')
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        @($results | Where-Object Outcome -NE 'Succeeded') | Should -BeNullOrEmpty
        Should -Invoke @m Save-RemoteFile -Times 1 -ParameterFilter { $Destination -like '*\cache\software\outil\outil.exe' }
        Should -Invoke @m Assert-TrustedExecutable -Times 2 -ParameterFilter { $ExpectedSigner -eq 'Éditeur Exemple' }
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -like '*outil.exe' -and $ArgumentList -eq '/S' }
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -like '*\msiexec.exe' -and $ArgumentList -match '^/i ".*outil\.msi" /qn /norestart ALLUSERS=1$' }
    }

    It 'signature refusée : rien n''est lancé' {
        Mock @m Assert-TrustedExecutable { throw 'signature invalide' }
        $selection = New-Selection
        $selection.ExtraSoftware.Ids = @('outil')
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[0].Outcome | Should -Be 'Failed'
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }

    It 'le plan garde l''entrée : un changement ultérieur du catalogue ne modifie pas l''exécution' {
        $selection = New-Selection
        $selection.ExtraSoftware.Ids = @('outil')
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $context.SoftwareCatalog = @()
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        $results[0].Outcome | Should -Be 'Succeeded'
    }
}

Describe 'Get-WingetSourceRepair' {
    It 'paramètres lus dans config.json, dossier dans le cache' {
        $context = New-TestContext -Folder $TestDrive
        $repair = Get-WingetSourceRepair -Context $context
        $repair.PackageUrl | Should -Be 'https://cdn.winget.microsoft.com/cache/source.msix'
        $repair.ExpectedSigner | Should -Be 'CN=Microsoft Corporation'
        $repair.Folder | Should -Be (Join-Path $context.Paths.Cache 'winget-source')
    }
    It 'bloc absent : $null (seconde tentative sautée)' {
        $config = Get-TestConfig
        $config.Winget.PSObject.Properties.Remove('SourcePackage')
        Get-WingetSourceRepair -Context (New-TestContext -Folder $TestDrive -Config $config) | Should -BeNullOrEmpty
    }
    It 'le test du catalogue transmet la réparation à winget' {
        $context = New-TestContext -Folder $TestDrive
        Mock -ModuleName FastPrepare.Application Test-Winget { $true }
        Mock -ModuleName FastPrepare.Application Get-WingetPackageInfo { [pscustomobject]@{ Name = 'x'; Version = '1' } }
        [void](Test-SoftwareCatalogEntry -Entry $context.SoftwareCatalog[0] -Context $context)
        Should -Invoke -ModuleName FastPrepare.Application Get-WingetPackageInfo -Times 1 -ParameterFilter { $SourceRepair.ExpectedSigner -eq 'CN=Microsoft Corporation' }
    }
}

Describe 'Installation winget avec portée (mode réel, simulacres)' {
    It 'la portée du catalogue est transmise à winget install' {
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $context.SoftwareCatalog = @(ConvertTo-SoftwareEntry -InputObject ([pscustomobject]@{ Id = 'vscode'; Label = 'Visual Studio Code'; Install = [pscustomobject]@{ Type = 'winget'; Id = 'Microsoft.VisualStudioCode'; Source = 'winget'; Scope = 'machine' } }))
        Mock -ModuleName FastPrepare.Application Assert-WingetAvailable { }
        Mock -ModuleName FastPrepare.Application Install-WingetPackage { [pscustomobject]@{ RebootRequired = $false; AlreadyInstalled = $false } }
        $selection = New-Selection
        $selection.ExtraSoftware.Ids = @('vscode')
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $plan.Actions[-1].Label | Should -Match '--scope machine'
        [void](Invoke-ExecutionPlan -Plan $plan -Context $context)
        Should -Invoke -ModuleName FastPrepare.Application Install-WingetPackage -Times 1 -ParameterFilter { $Id -eq 'Microsoft.VisualStudioCode' -and $Scope -eq 'machine' }
    }
}
