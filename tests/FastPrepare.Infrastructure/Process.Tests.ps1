BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Infrastructure
    $cmd = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
}

Describe 'Invoke-ExternalProcess (commandes inoffensives)' {
    It 'code 0 : succès' {
        $result = Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 0' -TimeoutMinutes 1
        $result.ExitCode | Should -Be 0
        $result.RebootRequired | Should -BeFalse
    }
    It 'code 3010 : succès avec redémarrage nécessaire' {
        (Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 3010' -TimeoutMinutes 1).RebootRequired | Should -BeTrue
    }
    It 'code inattendu : erreur avec la signification connue' {
        { Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 1603' -TimeoutMinutes 1 } | Should -Throw '*code de sortie 1603 (erreur fatale*'
    }
    It 'codes de succès propres à l''outil (-SuccessExitCode)' {
        (Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 5' -SuccessExitCode 0, 5 -TimeoutMinutes 1).ExitCode | Should -Be 5
    }
    It 'capture la sortie standard' {
        (Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c echo bonjour' -CaptureOutput -TimeoutMinutes 1).Output | Should -Match 'bonjour'
    }
    It 'exécutable introuvable : erreur explicite' {
        { Invoke-ExternalProcess -FilePath 'C:\absent\inexistant.exe' -TimeoutMinutes 1 } | Should -Throw '*Lancement impossible*'
    }
    It 'journalise la commande et le code de sortie (DEBUG, fichier seulement)' {
        $log = New-RunLog -Folder (Join-Path $TestDrive 'logs') -FallbackFolder (Join-Path $TestDrive 'r') -HostName 'PC' -Stamp 'p'
        [void](Invoke-ExternalProcess -FilePath $cmd -ArgumentList '/c exit 0' -TimeoutMinutes 1 -Log $log)
        $text = Get-Content -LiteralPath $log.FilePath -Raw -Encoding UTF8
        $text | Should -Match '\[DEBUG\] Commande : ".*cmd\.exe" /c exit 0'
        $text | Should -Match '\[DEBUG\] Code de sortie 0'
        @(Receive-RunLogEntry -Log $log).Count | Should -Be 0
    }
}

Describe 'Get-SystemExecutablePath' {
    It 'chemin absolu dans System32' {
        Get-SystemExecutablePath -Name 'powercfg.exe' | Should -Be (Join-Path ([Environment]::GetFolderPath('System')) 'powercfg.exe')
    }
}
