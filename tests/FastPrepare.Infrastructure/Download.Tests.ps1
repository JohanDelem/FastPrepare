BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Infrastructure
}

Describe 'Save-RemoteFile' {
    BeforeEach {
        # Aucun accès réseau : le transfert BITS est simulé par l'écriture d'un contenu connu.
        Mock -ModuleName FastPrepare.Infrastructure Start-BitsTransfer { Set-Content -LiteralPath $Destination -Value 'contenu' -NoNewline -Encoding Ascii }
        $expected = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::ASCII.GetBytes('contenu'))) -Algorithm SHA256).Hash
    }

    It 'refuse un lien qui n''est pas en https' {
        { Save-RemoteFile -Url 'http://exemple.test/a.exe' -Destination (Join-Path $TestDrive 'a.exe') } | Should -Throw '*https*'
    }
    It 'empreinte correcte : fichier final en place, aucun fichier partiel' {
        $target = Join-Path $TestDrive 'ok\a.exe'
        Save-RemoteFile -Url 'https://exemple.test/a.exe' -Destination $target -Sha256 $expected.ToLowerInvariant() | Should -Be $target
        $target | Should -Exist
        "$target.partiel" | Should -Not -Exist
    }
    It 'empreinte fausse : erreur et fichier supprimé' {
        $target = Join-Path $TestDrive 'ko\a.exe'
        { Save-RemoteFile -Url 'https://exemple.test/a.exe' -Destination $target -Sha256 ('0' * 64) } | Should -Throw '*Empreinte SHA-256 inattendue*'
        $target | Should -Not -Exist
        "$target.partiel" | Should -Not -Exist
    }
}

Describe 'Assert-TrustedExecutable' {
    BeforeAll { $notepad = Join-Path ([Environment]::GetFolderPath('System')) 'notepad.exe' }

    It 'exécutable Windows signé par Microsoft : accepté' {
        { Assert-TrustedExecutable -Path $notepad -ExpectedSigner 'Microsoft' } | Should -Not -Throw
    }
    It 'éditeur différent de celui attendu : refusé' {
        { Assert-TrustedExecutable -Path $notepad -ExpectedSigner 'Lenovo' } | Should -Throw '*non lancé*'
    }
    It 'fichier non signé : refusé' {
        $unsigned = Join-Path $TestDrive 'nonsigne.ps1'
        Set-Content -LiteralPath $unsigned -Value 'Write-Output 1'
        { Assert-TrustedExecutable -Path $unsigned -ExpectedSigner '' } | Should -Throw '*non valide*'
    }
}
