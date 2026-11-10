<#
    Fichier software.json (lecture, validation, écriture atomique) et adaptateurs du test sans
    téléchargement (winget show, en-têtes HTTP), tous simulés : aucun accès réseau.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
    $m = @{ ModuleName = 'FastPrepare.Infrastructure' }

    function New-Entry([string]$Id = '7-zip', [string]$Label = '7-Zip') {
        ConvertTo-SoftwareEntry -InputObject ([pscustomobject]@{ Id = $Id; Label = $Label; DefaultChecked = $true; Install = [pscustomobject]@{ Type = 'winget'; Id = '7zip.7zip'; Source = 'winget' } })
    }
    function Write-Catalog([string]$Path, [string]$Json) { [System.IO.File]::WriteAllText($Path, $Json, (New-Object System.Text.UTF8Encoding($false))) }
}

Describe 'Read-SoftwareCatalog' {
    It 'software.json du dépôt : valide' {
        $catalog = Read-SoftwareCatalog -Path (Join-Path (Get-RepoRoot) 'software.json')
        @($catalog.Entries).Count | Should -BeGreaterThan 0
        $catalog.Entries[0].Install.Type | Should -Be 'winget'
    }
    It 'fichier absent : catalogue vide et avertissement' {
        $catalog = Read-SoftwareCatalog -Path (Join-Path $TestDrive 'absent.json')
        @($catalog.Entries).Count | Should -Be 0
        $catalog.Warnings[0] | Should -Match 'introuvable'
    }
    It 'refus : <Why>' -ForEach @(
        @{ Why = 'JSON invalide'; Json = '{ "CatalogVersion": 1, '; Pattern = "n'est pas un JSON valide" }
        @{ Why = 'version inconnue'; Json = '{ "CatalogVersion": 2, "Software": [] }'; Pattern = 'CatalogVersion 1 attendue' }
        @{ Why = 'liste absente'; Json = '{ "CatalogVersion": 1 }'; Pattern = 'Software' }
        @{ Why = 'doublon'; Json = '{ "CatalogVersion": 1, "Software": [ { "Id": "a", "Label": "A", "Install": { "Type": "winget", "Id": "x.y", "Source": "winget" } }, { "Id": "a", "Label": "B", "Install": { "Type": "winget", "Id": "x.z", "Source": "winget" } } ] }'; Pattern = 'Software\[1\] \(B\) — Identifiant interne' }
        @{ Why = 'lien http'; Json = '{ "CatalogVersion": 1, "Software": [ { "Id": "a", "Label": "A", "Install": { "Type": "download", "Url": "http://x.test/a.exe", "FileName": "a.exe", "ExpectedSigner": "E" } } ] }'; Pattern = 'https' }
    ) {
        $path = Join-Path $TestDrive 'catalogue.json'
        Write-Catalog $path $Json
        $message = try { [void](Read-SoftwareCatalog -Path $path); '' } catch { $_.Exception.Message }
        $message | Should -Match $Pattern
    }
    It 'catalogue vide accepté' {
        $path = Join-Path $TestDrive 'vide.json'
        Write-Catalog $path '{ "CatalogVersion": 1, "Software": [] }'
        @((Read-SoftwareCatalog -Path $path).Entries).Count | Should -Be 0
    }
}

Describe 'Save-SoftwareCatalog' {
    It 'écrit, garde l''ancienne version en .bak, relit à l''identique' {
        $path = Join-Path $TestDrive 'ecriture.json'
        Write-Catalog $path '{ "CatalogVersion": 1, "Software": [] }'
        $result = Save-SoftwareCatalog -Path $path -Entries @((New-Entry), (New-Entry -Id 'autre' -Label 'Autre éditeur'))
        $result.Backup | Should -Be "$path.bak"
        [System.IO.File]::ReadAllText("$path.bak") | Should -Match '"Software": \[\]'
        $relu = (Read-SoftwareCatalog -Path $path).Entries
        @($relu).Id | Should -Be @('7-zip', 'autre')
        $relu[1].Label | Should -Be 'Autre éditeur'
        Test-Path -LiteralPath "$path.tmp" | Should -BeFalse
    }
    It 'JSON indenté sur deux espaces, sans BOM' {
        $path = Join-Path $TestDrive 'format.json'
        [void](Save-SoftwareCatalog -Path $path -Entries @(New-Entry))
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0] | Should -Be ([byte][char]'{')
        $text = [System.IO.File]::ReadAllText($path)
        $text | Should -Match '(?m)^  "CatalogVersion": 1,\r?$'
        $text | Should -Match '(?m)^      "Label": "7-Zip",\r?$'
    }
    It 'un seul logiciel reste une liste ; catalogue vide écrit « [] »' {
        $path = Join-Path $TestDrive 'un.json'
        [void](Save-SoftwareCatalog -Path $path -Entries @(New-Entry))
        ([System.IO.File]::ReadAllText($path) | ConvertFrom-Json).Software -is [array] | Should -BeTrue
        [void](Save-SoftwareCatalog -Path $path -Entries @())
        [System.IO.File]::ReadAllText($path) | Should -Match '"Software": \[\]'
    }
    It 'entrée invalide : rien n''est écrit' {
        $path = Join-Path $TestDrive 'refus.json'
        Write-Catalog $path '{ "CatalogVersion": 1, "Software": [] }'
        $bad = New-Entry; $bad.Install.Id = 'avec espace'
        { Save-SoftwareCatalog -Path $path -Entries @($bad) } | Should -Throw '*Identifiant winget*'
        [System.IO.File]::ReadAllText($path) | Should -Match '"Software": \[\]'
    }
    It 'dossier protégé en écriture : message explicite' {
        Mock @m Test-Path { $false }
        Mock @m Move-Item { throw [System.UnauthorizedAccessException]::new('Accès refusé') }
        { Save-SoftwareCatalog -Path (Join-Path $TestDrive 'protege.json') -Entries @(New-Entry) } | Should -Throw '*protégée en écriture*'
    }
}

Describe 'Get-WingetPackageInfo' {
    BeforeEach { Mock @m Get-Command { [pscustomobject]@{ Source = 'C:\winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' } }

    It 'nom et version lus dans la sortie (français), winget show seulement' {
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; Output = "Trouvé 7-Zip [7zip.7zip]`r`nVersion : 24.09`r`nÉditeur : Igor Pavlov" } }
        $info = Get-WingetPackageInfo -Id '7zip.7zip' -Source 'winget'
        $info.Name | Should -Be '7-Zip'
        $info.Version | Should -Be '24.09'
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $ArgumentList -like 'show --id 7zip.7zip --exact --source winget*' -and $ArgumentList -notmatch 'install|download' }
    }
    It 'installateur détecté (français) : fichier lu à la ligne qui précède l''empreinte' {
        $output = "Trouvé Microsoft Visual Studio Code [Microsoft.VisualStudioCode]`r`nVersion : 1.143.1`r`nProgramme d'installation :`r`n  Type du programme d’installation : inno`r`n  URL du programme d’installation : https://vscode.download.prss.microsoft.com/dbazure/download/stable/e6/VSCodeSetup-x64-1.143.1.exe`r`n  SHA256 du programme d’installation : $('ab' * 32)`r`n"
        $detail = ConvertFrom-WingetShowDetail -Output $output -Id 'Microsoft.VisualStudioCode'
        $detail.InstallerFound | Should -BeTrue
        $detail.InstallerFile | Should -Be 'VSCodeSetup-x64-1.143.1.exe'
    }
    It 'installateur détecté (anglais)' {
        $output = "Found 7-Zip [7zip.7zip]`nVersion: 26.06`nInstaller:`n  Installer Type: wix`n  Installer Url: https://www.7-zip.org/a/7z2606-x64.msi`n  Installer SHA256: $('CD' * 32)`n"
        (ConvertFrom-WingetShowDetail -Output $output -Id '7zip.7zip').InstallerFile | Should -Be '7z2606-x64.msi'
    }
    It 'aucun installateur pour la portée (winget répond pourtant 0) : InstallerFound faux' {
        $detail = ConvertFrom-WingetShowDetail -Output "Trouvé 7-Zip [7zip.7zip]`r`nVersion : 26.06`r`nÉditeur : Igor Pavlov`r`n" -Id '7zip.7zip'
        $detail.InstallerFound | Should -BeFalse
        $detail.InstallerFile | Should -Be ''
    }
    It '--scope transmis à winget show et winget install' {
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; Output = "Trouvé 7-Zip [7zip.7zip]`r`nVersion : 26.06"; RebootRequired = $false } }
        [void](Get-WingetPackageInfo -Id '7zip.7zip' -Source 'winget' -Scope 'machine')
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $ArgumentList -like 'show --id 7zip.7zip*--scope machine' }
        Get-WingetInstallArgument -Id '7zip.7zip' -Source 'winget' -Scope 'machine' | Should -Match ' --scope machine'
        Get-WingetInstallArgument -Id '7zip.7zip' -Source 'winget' | Should -Not -Match 'scope'
    }
    It 'sortie anglaise' {
        (ConvertFrom-WingetShowDetail -Output "Found Adobe Acrobat Reader (64-bit) [Adobe.Acrobat.Reader.64-bit]`nVersion: 25.001" -Id 'Adobe.Acrobat.Reader.64-bit').Name | Should -Be 'Adobe Acrobat Reader (64-bit)'
    }
    It 'paquet introuvable : message clair' {
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = -1978335212; Output = 'Aucun package ne correspond' } }
        { Get-WingetPackageInfo -Id 'inconnu.paquet' -Source 'winget' } | Should -Throw '*introuvable dans la source*'
    }
}

Describe 'Test-RemoteFile' {
    It 'HEAD suffit : en-têtes renvoyés' {
        Mock @m Invoke-HttpHeaderRequest { [pscustomobject]@{ StatusCode = 200; ContentType = 'application/octet-stream'; ContentLength = 1048576; FinalUrl = $Url } }
        $result = Test-RemoteFile -Url 'https://exemple.test/a.exe'
        $result.StatusCode | Should -Be 200
        Should -Invoke @m Invoke-HttpHeaderRequest -Times 1 -ParameterFilter { $Method -eq 'HEAD' }
    }
    It 'HEAD refusé (405) : repli GET, en-têtes seulement' {
        Mock @m Invoke-HttpHeaderRequest { [pscustomobject]@{ StatusCode = 405; ContentType = ''; ContentLength = $null; FinalUrl = $Url } } -ParameterFilter { $Method -eq 'HEAD' }
        Mock @m Invoke-HttpHeaderRequest { [pscustomobject]@{ StatusCode = 200; ContentType = 'application/x-msdownload'; ContentLength = 10; FinalUrl = $Url } } -ParameterFilter { $Method -eq 'GET' }
        (Test-RemoteFile -Url 'https://exemple.test/a.exe').StatusCode | Should -Be 200
    }
    It 'lien http refusé sans requête' {
        Mock @m Invoke-HttpHeaderRequest { }
        { Test-RemoteFile -Url 'http://exemple.test/a.exe' } | Should -Throw '*https*'
        Should -Invoke @m Invoke-HttpHeaderRequest -Times 0
    }
}
