BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application

    $script:invoked = New-Object System.Collections.Generic.List[string]
    function New-TestAction([string]$StepId, [int]$Number, [string]$Label, [switch]$Interactive) {
        [pscustomobject]@{ PSTypeName = 'FastPrepare.StepAction'; Label = $Label; Parameters = @{}; Details = @('détail'); Interactive = [bool]$Interactive; StepId = $StepId; StepNumber = $Number; Section = 2; Index = $Number }
    }
    function New-TestPlan {
        [pscustomobject]@{
            Actions       = @(
                (New-TestAction 'ok-1' 1 'première')
                (New-TestAction 'panne' 2 'deuxième')
                (New-TestAction 'redemarrage' 3 'troisième' -Interactive)
                (New-TestAction 'absente' 4 'quatrième')
            )
            Warnings      = @('Section 3 : avertissement de test')
            StepCount     = 13
            InventoryPath = 'C:\Cle\logs\Inventaire_SN0000TEST_test.txt'
        }
    }
    $catalog = @{
        'ok-1'        = [pscustomobject]@{ Id = 'ok-1'; Invoke = { param($a, $c) $script:invoked.Add('ok-1') } }
        'panne'       = [pscustomobject]@{ Id = 'panne'; Invoke = { param($a, $c) $script:invoked.Add('panne'); throw 'code de sortie 1603' } }
        'redemarrage' = [pscustomobject]@{ Id = 'redemarrage'; Invoke = { param($a, $c) $script:invoked.Add('redemarrage'); [pscustomobject]@{ RebootRequired = $true } } }
        'absente'     = [pscustomobject]@{ Id = 'absente'; Invoke = $null }
    }
    function Get-Lines($Context) { @(Receive-RunLogEntry -Log $Context.Log) }
}

Describe 'Invoke-ExecutionPlan — simulation' {
    BeforeEach { $script:invoked.Clear() }

    It 'aucune action exécutée, une ligne par action, assistants en ATTN' {
        $context = New-TestContext -Folder $TestDrive -Mode Simulation
        $results = Invoke-ExecutionPlan -Plan (New-TestPlan) -Context $context -StepCatalog $catalog
        $script:invoked.Count | Should -Be 0
        @($results | Where-Object Outcome -EQ 'Simulated').Count | Should -Be 4
        $entries = Get-Lines $context
        @($entries | Where-Object { $_.Line -match '\[ETAPE \d\d/13 · section 2\]' }).Count | Should -Be 4
        ($entries | Where-Object { $_.Level -ne 'PROGRESS' -and $_.Line -match 'troisième' }).Level | Should -Be 'ATTN'
        ($entries.Line -join "`n") | Should -Match 'avertissement de test'
        ($entries.Line -join "`n") | Should -Match 'simulation terminée : 4 action\(s\)'
    }
}

Describe 'Invoke-ExecutionPlan — réel' {
    BeforeEach { $script:invoked.Clear() }

    It 'une action en échec est notée en rouge et les suivantes s''exécutent ; une étape sans Invoke est ignorée et signalée' {
        $context = New-TestContext -Folder $TestDrive -Mode Real
        $results = Invoke-ExecutionPlan -Plan (New-TestPlan) -Context $context -StepCatalog $catalog
        @($script:invoked) | Should -Be @('ok-1', 'panne', 'redemarrage')
        @($results).Outcome | Should -Be @('Succeeded', 'Failed', 'Succeeded', 'Skipped')
        $results[1].Error | Should -Be 'code de sortie 1603'
        $entries = Get-Lines $context
        ($entries | Where-Object { $_.Level -eq 'ERREUR' -and $_.Line -match 'deuxième : code de sortie 1603' }) | Should -Not -BeNullOrEmpty
        ($entries | Where-Object { $_.Level -eq 'ATTN' -and $_.Line -match 'quatrième — pas encore disponible en mode réel' }) | Should -Not -BeNullOrEmpty
        @($entries | Where-Object { $_.Level -eq 'ERREUR' -and $_.Line -match 'quatrième' }).Count | Should -Be 0
    }

    It 'rapport final : bilan, échecs rappelés, redémarrage nécessaire, inventaire, rappels manuels' {
        $context = New-TestContext -Folder $TestDrive -Mode Real
        [void](Invoke-ExecutionPlan -Plan (New-TestPlan) -Context $context -StepCatalog $catalog)
        $text = (Get-Lines $context).Line -join "`n"
        $text | Should -Match '2 action\(s\) réussie\(s\), 1 en échec, 1 ignorée\(s\)'
        $text | Should -Match 'Échec : \[ETAPE 02/13 · section 2\] deuxième'
        $text | Should -Match 'Redémarrage nécessaire'
        $text | Should -Match 'Inventaire_SN0000TEST'
        $text | Should -Match ([regex]::Escape((Get-TestConfig).ManualReminders[0]))
    }
}

Describe 'Plan réel de bout en bout en simulation' {
    It 'le plan construit par les étapes passe dans le moteur avec le catalogue du module' {
        $context = New-TestContext -Folder $TestDrive -Mode Simulation
        $selection = New-Selection
        $selection.Updates.WindowsUpdate = $true
        $selection.HostName.Enabled = $true; $selection.HostName.Name = 'PC-02'
        $plan = New-ExecutionPlan -Selection $selection -Snapshot (New-TestSnapshot) -Context $context
        $results = Invoke-ExecutionPlan -Plan $plan -Context $context
        @($results).Count | Should -Be 2
        $text = (Get-Lines $context).Line -join "`n"
        $text | Should -Match '\[ETAPE 12/13 · section 7\] Windows Update'
        $text | Should -Match "\[ETAPE 13/13 · section 1\] Nom d'hôte : Rename-Computer -NewName 'PC-02'"
    }
}
