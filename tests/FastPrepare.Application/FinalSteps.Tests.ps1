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
        Mock @m Copy-RunLogToDrive { [pscustomobject]@{ Copied = @('x'); Destination = 'E:\logs'; Error = $null } }
        $context = New-TestContext -Folder $TestDrive -Mode Simulation
        $context.Log.IsFallback = $true
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        [void](Invoke-ExecutionPlan -Plan $plan -Context $context)
        Should -Invoke @m Copy-RunLogToDrive -Times 1 -ParameterFilter { $AdditionalFile -contains 'C:\Cle\logs\Inventaire_SN0000TEST_test.txt' }
        ((Receive-RunLogEntry -Log $context.Log).Line -join "`n") | Should -Match 'copiés sur la clé : E:\\logs'
    }
    It 'copie impossible : consigne de copie manuelle' {
        Mock @m Copy-RunLogToDrive { [pscustomobject]@{ Copied = @(); Destination = 'E:\logs'; Error = 'dossier toujours en lecture seule' } }
        $context = New-TestContext -Folder $TestDrive -Mode Simulation
        $context.Log.IsFallback = $true
        $plan = New-ExecutionPlan -Selection (New-Selection) -Snapshot (New-TestSnapshot) -Context $context
        [void](Invoke-ExecutionPlan -Plan $plan -Context $context)
        ((Receive-RunLogEntry -Log $context.Log) | Where-Object Level -EQ 'ATTN').Line -join "`n" | Should -Match 'copiez-le à la main'
    }
}
