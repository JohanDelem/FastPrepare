<#
    Itération 7 : Windows Update en mode réel, avancement, copie du journal en fin d'exécution.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
    $m = @{ ModuleName = 'FastPrepare.Application' }
    function Invoke-WindowsUpdateStep($Context) {
        $selection = New-Selection
        $selection.Updates.WindowsUpdate = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $Context
        return (Invoke-ExecutionPlan -Plan $plan -Context $Context)
    }
}

Describe 'Étape 12 en mode réel — Windows Update' {
    It 'passe réussie : bilan journalisé, redémarrage signalé' {
        Mock @m Invoke-WindowsUpdatePass { [pscustomobject]@{ Found = 3; Installed = 3; Failed = @(); RebootRequired = $true; Remaining = 0 } }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $results = Invoke-WindowsUpdateStep $context
        $results[0].Outcome | Should -Be 'Succeeded'
        $results[0].RebootRequired | Should -BeTrue
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match '3 installée\(s\) sur 3'
    }
    It 'mises à jour restantes après la passe : avertissement, pas d''échec' {
        Mock @m Invoke-WindowsUpdatePass { [pscustomobject]@{ Found = 1; Installed = 1; Failed = @(); RebootRequired = $false; Remaining = 4 } }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        (Invoke-WindowsUpdateStep $context)[0].Outcome | Should -Be 'Succeeded'
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match '4 mise\(s\) à jour encore disponible'
    }
    It 'mises à jour en échec : action en échec avec leurs titres, redémarrage quand même signalé' {
        Mock @m Invoke-WindowsUpdatePass { [pscustomobject]@{ Found = 2; Installed = 1; Failed = @('KB999'); RebootRequired = $true; Remaining = 0 } }
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $results = Invoke-WindowsUpdateStep $context
        $results[0].Outcome | Should -Be 'Failed'
        $results[0].Error | Should -Match 'KB999'
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match 'redémarrage nécessaire pour finaliser'
    }
}

Describe 'Toutes les étapes du cahier disponibles en mode réel' {
    It 'chaque étape enregistrée a un Invoke' {
        @((Get-RegisteredStep).Values | Where-Object { -not $_.Invoke } | ForEach-Object Id) | Should -BeNullOrEmpty
    }
}

Describe 'Avancement et copie du journal' {
    It 'le moteur publie une progression par action (1..N)' {
        $context = New-TestContext -Folder $TestDrive -Mode Simulation
        $selection = New-Selection
        $selection.Updates.WindowsUpdate = $true
        $selection.SystemSettings.Power = $true
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        [void](Invoke-ExecutionPlan -Plan $plan -Context $context)
        $progress = @(Receive-RunLogEntry -Log $context.Log | Where-Object Level -EQ 'PROGRESS')
        @($progress.Current) | Should -Be @(1, 2)
        @($progress.Total | Sort-Object -Unique) | Should -Be @(2)
    }
    It 'journal en repli : copie tentée en fin de rapport, avec l''inventaire' {
        Mock @m Copy-RunLogToOutput { [pscustomobject]@{ Copied = @('x'); Destination = '\\serveur\partage\logs'; Error = $null } }
        $context = New-TestContext -Folder $TestDrive -Mode Simulation
        $context.Log.IsFallback = $true
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        [void](Invoke-ExecutionPlan -Plan $plan -Context $context)
        Should -Invoke @m Copy-RunLogToOutput -Times 1 -ParameterFilter { $AdditionalFile -contains 'C:\Outil\logs\Inventaire_SN0000TEST_test.txt' }
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match 'copiés dans le dossier de sortie : \\\\serveur\\partage\\logs'
    }
    It 'copie impossible : consigne de copie manuelle' {
        Mock @m Copy-RunLogToOutput { [pscustomobject]@{ Copied = @(); Destination = 'E:\logs'; Error = 'dossier toujours inaccessible en écriture' } }
        $context = New-TestContext -Folder $TestDrive -Mode Simulation
        $context.Log.IsFallback = $true
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        [void](Invoke-ExecutionPlan -Plan $plan -Context $context)
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match 'copiez-les à la main'
    }
}

Describe 'Rappels des actions manuelles (facultatifs)' {
    It 'sans ManualReminders : aucune ligne « À faire à la main »' {
        $config = Get-TestConfig
        $config.PSObject.Properties.Remove('ManualReminders')
        $context = New-TestContext -Folder $TestDrive -Mode Simulation -Config $config
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        [void](Invoke-ExecutionPlan -Plan $plan -Context $context)
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Not -Match 'À faire à la main'
        @(Get-ManualReminder -Config $config).Count | Should -Be 0
    }
    It 'avec ManualReminders : rappelés en fin de rapport' {
        $context = New-TestContext -Folder $TestDrive -Mode Simulation
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        [void](Invoke-ExecutionPlan -Plan $plan -Context $context)
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match 'À faire à la main : '
    }
}

Describe 'Nettoyage du dossier de travail en fin d''exécution (DEC28)' {
    BeforeEach {
        $m = @{ ModuleName = 'FastPrepare.Application' }
        Mock @m Set-PowerTimeout { }
        Mock @m Assert-WingetAvailable { }
        function New-WorkContext([string]$Name, [string]$Mode) {
            # Dossier de travail de test : <dossier>\cache et <dossier>\odt, comme sur un poste.
            $work = Join-Path $TestDrive $Name
            $context = New-TestContext -Folder $work -Mode $Mode
            $context.Paths.Odt = Join-Path $work 'odt'
            foreach ($folder in $context.Paths.Cache, $context.Paths.Odt) {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $folder 'fichier.bin') -Value 'x'
            }
            return $context
        }
        function Invoke-Run($Context, [string[]]$Catalog = @()) {
            $selection = New-Selection
            $selection.SystemSettings.Power = $true
            $selection.Catalog.Ids = $Catalog
            $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $Context
            return (Invoke-ExecutionPlan -Plan $plan -Context $Context)
        }
    }

    It 'exécution réelle sans échec d''installation : téléchargements et dossier ODT supprimés, journal conservé' {
        Mock @m Install-WingetPackage { [pscustomobject]@{ RebootRequired = $false; AlreadyInstalled = $false } }
        $context = New-WorkContext 'w1' 'Real'
        [void](Invoke-Run $context 'adobe-reader')
        $context.Paths.Cache | Should -Not -Exist
        $context.Paths.Odt | Should -Not -Exist
        $context.Log.FilePath | Should -Exist
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match 'Fichiers de travail supprimés'
    }

    It 'une installation a échoué : fichiers conservés pour le diagnostic, et signalés' {
        Mock @m Install-WingetPackage { throw 'code de sortie 1603' }
        $context = New-WorkContext 'w2' 'Real'
        [void](Invoke-Run $context 'adobe-reader')
        $context.Paths.Cache | Should -Exist
        $context.Paths.Odt | Should -Exist
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match 'Fichiers de travail conservés pour le diagnostic'
    }

    It 'simulation : rien n''est supprimé (aucune modification du poste)' {
        $context = New-WorkContext 'w3' 'Simulation'
        [void](Invoke-Run $context)
        $context.Paths.Cache | Should -Exist
        $context.Paths.Odt | Should -Exist
    }

    It 'dossier hors du dossier de travail : suppression refusée par la garde de chemin, signalée' {
        $context = New-WorkContext 'w4' 'Real'
        $outside = Join-Path $TestDrive 'ailleurs'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        $context.Paths.Odt = $outside
        [void](Invoke-Run $context)
        $outside | Should -Exist
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match 'Fichiers de travail non supprimés'
    }
}
