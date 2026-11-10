<#
    Moteur d'exécution : exécute un plan. Seul fichier qui connaît le mode (simulation ou réel).
    Règle du cahier : « Si une étape échoue, l'outil la note en rouge dans le journal et passe à
    la suivante. » Une erreur est capturée au niveau de l'action, jamais propagée.
#>

function Invoke-ExecutionPlan {
    <#
        Exécute le plan dans le mode du contexte, puis écrit le rapport final.
        -StepCatalog : table Id → étape (par défaut le catalogue du module ; injectable pour les tests).
        Renvoie les résultats { Action, Outcome, Error, RebootRequired, Duration }.
        Outcome : 'Simulated', 'Succeeded', 'Failed' ou 'Skipped' (étape pas encore disponible en
        mode réel : signalée, jamais exécutée à moitié).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Context,
        [hashtable]$StepCatalog
    )

    if (-not $StepCatalog) { $StepCatalog = Get-RegisteredStep }
    $log = $Context.Log
    $simulation = ($Context.Mode -eq 'Simulation')
    $actions = @($Plan.Actions)

    $title = if ($simulation) { 'Simulation' } else { 'Exécution' }
    Write-RunLog -Log $log -Level $(if ($simulation) { 'SIMU' } else { 'INFO' }) -Message ("===== {0} : {1} =====" -f $title, (Format-ExecutionPlanSummary -Plan $Plan))
    foreach ($warning in @($Plan.Warnings)) { Write-RunLog -Log $log -Level ATTN -Message $warning }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($action in $actions) {
        $prefix = Format-ActionPrefix -Action $action -StepCount $Plan.StepCount
        Publish-RunProgress -Log $log -Current $action.Index -Total $actions.Count -Label $action.Label
        $started = Get-Date
        $result = [pscustomobject]@{ Action = $action; Outcome = $null; Error = $null; RebootRequired = $false; Duration = [TimeSpan]::Zero }

        if ($simulation) {
            $level = if ($action.Interactive) { 'ATTN' } else { 'SIMU' }
            Write-RunLog -Log $log -Level $level -Message ($prefix + $action.Label)
            foreach ($line in @($action.Details)) { Write-RunLog -Log $log -Level SIMU -Message ('     ' + $line) }
            $result.Outcome = 'Simulated'
        } else {
            $step = $StepCatalog[$action.StepId]
            if (-not $step -or -not $step.Invoke) {
                $result.Outcome = 'Skipped'
                $result.Error = 'pas encore disponible en mode réel dans cette version : ignorée'
                Write-RunLog -Log $log -Level ATTN -Message ('{0}{1} — {2}' -f $prefix, $action.Label, $result.Error)
            } else {
                Write-RunLog -Log $log -Level $(if ($action.Interactive) { 'ATTN' } else { 'INFO' }) -Message ($prefix + $action.Label)
                foreach ($line in @($action.Details)) { Write-RunLog -Log $log -Level DEBUG -Message ('     ' + $line) }
                try {
                    $output = @(& $step.Invoke $action $Context)
                    $result.RebootRequired = [bool](@($output | Where-Object { $_ -and $_.PSObject.Properties['RebootRequired'] -and $_.RebootRequired }).Count)
                    $result.Outcome = 'Succeeded'
                    Write-RunLog -Log $log -Level OK -Message ('{0}terminé ({1:N0} s)' -f $prefix, ((Get-Date) - $started).TotalSeconds)
                } catch {
                    $result.Outcome = 'Failed'
                    $result.Error = $_.Exception.Message
                    Write-RunLog -Log $log -Level ERREUR -Message ('{0}{1} : {2}' -f $prefix, $action.Label, $result.Error)
                }
            }
        }
        $result.Duration = (Get-Date) - $started
        $results.Add($result)
    }

    Write-FinalReport -Plan $Plan -Result $results.ToArray() -Context $Context
    return $results.ToArray()
}

function Start-ExecutionPlan {
    <# Lance Invoke-ExecutionPlan dans un runspace (la fenêtre reste réactive). Renvoie le travail. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Context
    )
    return Start-BackgroundWork -Name 'execution' -ModulePath $Context.ModulePaths -Argument @($Plan, $Context) -ScriptBlock {
        param($Plan, $Context)
        Invoke-ExecutionPlan -Plan $Plan -Context $Context
    }
}

function Format-ActionPrefix {
    <# Préfixe d'une ligne d'action : rang dans l'ordre du cahier et section de l'interface (contrat §8.2). #>
    param($Action, [int]$StepCount)
    return ('[ETAPE {0:00}/{1} · section {2}] ' -f $Action.StepNumber, $StepCount, $Action.Section)
}
