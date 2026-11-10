<#
    Plan d'exécution : liste ordonnée des actions à faire, construite par les étapes à partir de
    la sélection. Le MÊME plan sert à la simulation et à l'exécution réelle.
#>

function New-ExecutionPlan {
    <#
        Vérifie la cohérence de la sélection (Test-Selection), puis appelle le Plan de chaque étape
        dans l'ordre du cahier. Renvoie { Actions, Warnings, StepCount, InventoryPath }.
        Erreur si la sélection est incohérente.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Selection,
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)]$Context
    )

    $problems = @(Test-Selection -Selection $Selection -Config $Context.Config -Snapshot $Snapshot)
    if ($problems.Count -gt 0) {
        throw ("Sélection incohérente, plan non construit :`n- " + ($problems -join "`n- "))
    }

    $order = @(Get-StepOrder)
    $actions = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]

    for ($rank = 0; $rank -lt $order.Count; $rank++) {
        $step = Get-RegisteredStep -Id $order[$rank]
        foreach ($item in @(& $step.Plan $Selection $Snapshot $Context)) {
            if ($null -eq $item) { continue }
            if ($item.PSObject.TypeNames -contains 'FastPrepare.PlanWarning') {
                $warnings.Add(('Section {0} : {1}' -f $step.Section, $item.Message))
            } elseif ($item.PSObject.TypeNames -contains 'FastPrepare.StepAction') {
                $item.StepId = $step.Id
                $item.StepNumber = $rank + 1
                $item.Section = $step.Section
                $item.RealModeAvailable = [bool]$step.Invoke
                $actions.Add($item)
            } else {
                throw "L'étape '$($step.Id)' a produit un objet inattendu (New-StepAction ou New-PlanWarning attendu)."
            }
        }
    }

    for ($i = 0; $i -lt $actions.Count; $i++) { $actions[$i].Index = $i + 1 }

    $inventoryPath = $null
    if ($Snapshot.PSObject.Properties['InventoryExport'] -and $Snapshot.InventoryExport) { $inventoryPath = $Snapshot.InventoryExport.Path }

    return [pscustomobject]@{
        PSTypeName    = 'FastPrepare.ExecutionPlan'
        Mode          = [string]$Context.Mode
        Actions       = $actions.ToArray()
        Warnings      = $warnings.ToArray()
        StepCount     = $order.Count
        InventoryPath = $inventoryPath
    }
}

function Format-ExecutionPlanSummary {
    <# Résumé lisible : « 13 action(s), dont 2 désinstallation(s) avec assistant ». #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Plan)

    $count = @($Plan.Actions).Count
    if ($count -eq 0) { return 'Aucune action cochée.' }
    $interactive = @($Plan.Actions | Where-Object { $_.Interactive }).Count
    $text = '{0} action(s)' -f $count
    if ($interactive -gt 0) { $text += ', dont {0} avec assistant à suivre à l''écran' -f $interactive }
    if ($Plan.PSObject.Properties['Mode'] -and $Plan.Mode -eq 'Real') {
        $unavailable = @($Plan.Actions | Where-Object { -not $_.RealModeAvailable }).Count
        if ($unavailable -gt 0) { $text += (' · {0} non disponible(s) en mode réel dans cette version, ignorée(s)' -f $unavailable) }
    }
    if (@($Plan.Warnings).Count -gt 0) { $text += (' · {0} avertissement(s)' -f @($Plan.Warnings).Count) }
    return $text
}
