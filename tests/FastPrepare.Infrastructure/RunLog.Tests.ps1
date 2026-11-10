BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Infrastructure
}

Describe 'Journal d''exécution (contrat §8)' {
    BeforeEach {
        $log = New-RunLog -Folder (Join-Path $TestDrive 'logs') -FallbackFolder (Join-Path $TestDrive 'repli') -HostName 'PC1' -Stamp '20261110-104718'
    }

    It 'nom de fichier Journal_<hôte>_<horodatage>.log' {
        Split-Path $log.FilePath -Leaf | Should -Be 'Journal_PC1_20261110-104718.log'
        $log.IsFallback | Should -BeFalse
    }

    It 'ligne au format HH:mm:ss [NIVEAU] message, fichier UTF-8 avec BOM' {
        Write-RunLog -Log $log -Level OK -Message 'Connexion validée'
        $bytes = [System.IO.File]::ReadAllBytes($log.FilePath)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        @(Get-Content -LiteralPath $log.FilePath -Encoding UTF8)[0] | Should -Match '^\d{2}:\d{2}:\d{2} \[OK\] Connexion validée$'
    }

    It 'publie dans la file pour l''interface, sauf DEBUG (fichier seulement)' {
        Write-RunLog -Log $log -Message 'visible'
        Write-RunLog -Log $log -Level DEBUG -Message 'technique'
        $entries = Receive-RunLogEntry -Log $log
        @($entries).Count | Should -Be 1
        $entries[0].Level | Should -Be 'INFO'
        (Get-Content -LiteralPath $log.FilePath -Encoding UTF8) -join "`n" | Should -Match 'technique'
        @(Receive-RunLogEntry -Log $log).Count | Should -Be 0
    }

    It 'dossier non accessible en écriture : repli' {
        $blocked = Join-Path $TestDrive 'fichier'
        Set-Content -LiteralPath $blocked -Value 'x'
        $fallbackLog = New-RunLog -Folder (Join-Path $blocked 'sous-dossier') -FallbackFolder (Join-Path $TestDrive 'repli') -HostName 'PC1' -Stamp 's'
        $fallbackLog.IsFallback | Should -BeTrue
        $fallbackLog.Folder | Should -Be (Join-Path $TestDrive 'repli')
    }

    It 'échec d''écriture du fichier : signalé une fois dans la file, puis suspendu' {
        $log.FilePath = Join-Path $TestDrive 'absent\x\journal.log'
        Write-RunLog -Log $log -Message 'un'
        Write-RunLog -Log $log -Message 'deux'
        $entries = Receive-RunLogEntry -Log $log
        @($entries | Where-Object Level -EQ 'ATTN').Count | Should -Be 1
        @($entries | Where-Object Level -EQ 'INFO').Count | Should -Be 2
    }
}
