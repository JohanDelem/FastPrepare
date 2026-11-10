BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
    $corePath = Join-Path (Get-RepoRoot) 'src\FastPrepare.Core\FastPrepare.Core.psd1'
    $infraPath = Join-Path (Get-RepoRoot) 'src\FastPrepare.Infrastructure\FastPrepare.Infrastructure.psd1'

    function Wait-Work($Work, [int]$TimeoutSeconds = 30) {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not (Test-BackgroundWorkCompleted -Work $Work)) {
            if ((Get-Date) -gt $deadline) { throw 'Délai dépassé' }
            Start-Sleep -Milliseconds 50
        }
    }
}

Describe 'Travaux d''arrière-plan' {
    It 'exécute le bloc dans un autre fil, avec ses arguments et les modules demandés' {
        $work = Start-BackgroundWork -Name 'test' -ModulePath @($corePath) -Argument @('PC-01', 2) -ScriptBlock {
            param($Name, $Factor)
            [pscustomobject]@{ Valid = (Test-HostName -Name $Name); Double = $Factor * 2; Thread = [System.Threading.Thread]::CurrentThread.ManagedThreadId }
        }
        Wait-Work $work
        $result = @(Receive-BackgroundWork -Work $work)[0]
        $result.Valid | Should -BeTrue
        $result.Double | Should -Be 4
        $result.Thread | Should -Not -Be ([System.Threading.Thread]::CurrentThread.ManagedThreadId)
    }

    It 'ne bloque pas l''appelant pendant le travail' {
        $work = Start-BackgroundWork -Name 'lent' -ScriptBlock { Start-Sleep -Seconds 2; 'fini' }
        Test-BackgroundWorkCompleted -Work $work | Should -BeFalse
        Wait-Work $work
        Receive-BackgroundWork -Work $work | Should -Be 'fini'
    }

    It 'une erreur du travail est relevée avec son nom' {
        $work = Start-BackgroundWork -Name 'en-echec' -ScriptBlock { throw 'panne simulée' }
        Wait-Work $work
        { Receive-BackgroundWork -Work $work } | Should -Throw "*'en-echec'*panne simulée*"
    }

    It 'module introuvable : erreur immédiate' {
        { Start-BackgroundWork -Name 'x' -ModulePath @('C:\absent\x.psd1') -ScriptBlock { 1 } } | Should -Throw '*introuvable*'
    }

    It 'le journal est partagé : écritures simultanées des deux fils, aucune perte' {
        $log = New-RunLog -Folder (Join-Path $TestDrive 'logs') -FallbackFolder (Join-Path $TestDrive 'repli') -HostName 'PC1' -Stamp 'concurrence'
        $work = Start-BackgroundWork -Name 'journal' -ModulePath @($infraPath) -Argument @($log) -ScriptBlock {
            param($Log)
            for ($i = 0; $i -lt 300; $i++) { Write-RunLog -Log $Log -Message "arrière-plan $i" }
        }
        for ($i = 0; $i -lt 300; $i++) { Write-RunLog -Log $log -Message "interface $i" }
        Wait-Work $work
        [void](Receive-BackgroundWork -Work $work)

        $log.FileFailed | Should -BeFalse
        @(Get-Content -LiteralPath $log.FilePath -Encoding UTF8).Count | Should -Be 600
        @(Receive-RunLogEntry -Log $log).Count | Should -Be 600
    }
}
