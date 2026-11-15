<#
    Contexte d'exécution : l'outil ne suppose rien de son support (DEC23). Le dossier de sortie
    est relatif au dossier de l'outil, absolu ou réseau ; inaccessible, il est remplacé par un
    dossier local du poste.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application

    function New-ToolFolder([string]$Name) {
        # Dossier d'outil minimal : catalogue et fichier VERSION.
        $tool = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $tool -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path (Get-RepoRoot) 'tests\Fixtures\software.test.json') -Destination (Join-Path $tool 'software.json')
        Set-Content -LiteralPath (Join-Path $tool 'VERSION') -Value '9.8.7'
        return $tool
    }
    function Get-ContextConfig([string]$Work) {
        $config = Get-TestConfig
        $config.Execution.WorkFolder = $Work
        return $config
    }
}

Describe 'New-AppContext — indépendance du support' {
    It 'dossier de sortie relatif : sous le dossier de l''outil' {
        $tool = New-ToolFolder 'outil1'
        $context = New-AppContext -Root $tool -Config (Get-ContextConfig (Join-Path $TestDrive 'travail1')) -RequestedMode Simulation
        $context.Paths.Tool | Should -Be $tool
        $context.Paths.Output | Should -Be (Join-Path $tool 'logs')
        $context.Log.IsFallback | Should -BeFalse
        $context.Version | Should -Be '9.8.7'
    }

    It 'dossier de sortie absolu : utilisé tel quel, rien n''est écrit dans le dossier de l''outil' {
        $tool = New-ToolFolder 'outil2'
        $config = Get-ContextConfig (Join-Path $TestDrive 'travail2')
        $config.Output.Folder = Join-Path $TestDrive 'collecte'
        $context = New-AppContext -Root $tool -Config $config -RequestedMode Simulation
        $context.Paths.Output | Should -Be (Join-Path $TestDrive 'collecte')
        $context.Log.FilePath | Should -BeLike (Join-Path $TestDrive 'collecte\Journal_*')
        Join-Path $tool 'logs' | Should -Not -Exist
    }

    It 'dossier de sortie inaccessible : repli dans <WorkFolder>\sortie, signalé' {
        $tool = New-ToolFolder 'outil3'
        $work = Join-Path $TestDrive 'travail3'
        $config = Get-ContextConfig $work
        $blocked = Join-Path $TestDrive 'bloque'
        Set-Content -LiteralPath $blocked -Value 'un fichier à la place du dossier'
        $config.Output.Folder = Join-Path $blocked 'sortie'
        $context = New-AppContext -Root $tool -Config $config -RequestedMode Simulation
        $context.Log.IsFallback | Should -BeTrue
        $context.Paths.Output | Should -Be (Join-Path $work 'sortie')
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match 'Dossier de sortie .+ non accessible en écriture'
    }

    It 'dossier de travail : cache et ODT dessous, variable WorkFolder' {
        $tool = New-ToolFolder 'outil4'
        $work = Join-Path $TestDrive 'travail4'
        $context = New-AppContext -Root $tool -Config (Get-ContextConfig $work) -RequestedMode Simulation
        $context.Paths.Work | Should -Be $work
        $context.Paths.Cache | Should -Be (Join-Path $work 'cache')
        $context.Paths.Odt | Should -Be (Join-Path $work 'odt')
        $context.Paths.Variables['WorkFolder'] | Should -Be $work
    }

    It 'paquet winget hors ligne : relatif au dossier de l''outil, vide s''il n''est pas configuré' {
        $tool = New-ToolFolder 'outil5'
        $config = Get-ContextConfig (Join-Path $TestDrive 'travail5')
        (New-AppContext -Root $tool -Config $config -RequestedMode Simulation).Paths.WingetBundle | Should -Be (Join-Path $tool $config.Winget.OfflineBundle)
        $config.Winget.PSObject.Properties.Remove('OfflineBundle')
        (New-AppContext -Root $tool -Config $config -RequestedMode Simulation).Paths.WingetBundle | Should -Be ''
    }

    It 'première ligne du journal : version et dossier de l''outil' {
        $tool = New-ToolFolder 'outil6'
        $context = New-AppContext -Root $tool -Config (Get-ContextConfig (Join-Path $TestDrive 'travail6')) -RequestedMode Simulation
        @(Get-Content -LiteralPath $context.Log.FilePath -Encoding UTF8)[0] | Should -Match 'FastPrepare 9\.8\.7 — dossier de l''outil : '
    }
}
