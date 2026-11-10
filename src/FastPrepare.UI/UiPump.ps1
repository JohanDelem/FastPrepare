<#
    Pompe de l'interface : le seul DispatcherTimer de l'application.
    À chaque battement, elle vide la file du journal vers la vue, appelle les traitements
    périodiques enregistrés (test de connexion) et détecte la fin des travaux d'arrière-plan
    pour appeler leur rappel sur le fil de l'interface. Une erreur dans un traitement est
    journalisée, jamais propagée.
#>

$script:UiPumpTimer = $null
$script:UiPumpLog = $null
$script:UiTickHandlers = [ordered]@{}
$script:UiPendingWorks = New-Object System.Collections.Generic.List[object]

function Register-UiBackgroundWork {
    <#
        Suit un travail d'arrière-plan (Start-BackgroundWork) : à sa fin, -OnCompleted reçoit son
        résultat, ou -OnFailed le message d'erreur. Les deux rappels s'exécutent sur le fil de
        l'interface : ils peuvent modifier les contrôles.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Work,
        [Parameter(Mandatory)][scriptblock]$OnCompleted,
        [Parameter(Mandatory)][scriptblock]$OnFailed
    )
    $script:UiPendingWorks.Add([pscustomobject]@{ Work = $Work; OnCompleted = $OnCompleted; OnFailed = $OnFailed })
}

function Test-UiBackgroundWorkPending {
    <# Vrai si au moins un travail d'arrière-plan suivi n'est pas terminé. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return ($script:UiPendingWorks.Count -gt 0)
}

function Register-UiTickHandler {
    <# Enregistre un traitement appelé à chaque battement (≈ 200 ms). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    $script:UiTickHandlers[$Name] = $ScriptBlock
}

function Start-UiPump {
    <# Démarre la pompe. Le minuteur ne bat que pendant la boucle de messages de la fenêtre. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Log,
        [int]$IntervalMilliseconds = 200
    )
    $script:UiPumpLog = $Log
    $script:UiPumpTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:UiPumpTimer.Interval = [TimeSpan]::FromMilliseconds($IntervalMilliseconds)
    $script:UiPumpTimer.Add_Tick({ Invoke-UiPumpTick })
    $script:UiPumpTimer.Start()
}

function Stop-UiPump {
    <# Arrête la pompe et affiche les dernières lignes du journal. #>
    [CmdletBinding()]
    param()
    if ($script:UiPumpTimer) { $script:UiPumpTimer.Stop() }
    foreach ($pending in $script:UiPendingWorks.ToArray()) { Stop-BackgroundWork -Work $pending.Work }
    $script:UiPendingWorks.Clear()
    if ($script:UiPumpLog) { Invoke-UiLogDrain }
}

function Invoke-UiPumpTick {
    # Rien ne doit remonter d'un battement : une exception dans la boucle de messages WPF fermerait la fenêtre.
    try {
        Invoke-UiLogDrain
        Invoke-UiBackgroundWorkCheck
    } catch {
        Write-RunLog -Log $script:UiPumpLog -Level ERREUR -Message ("Erreur interface (pompe) : {0}" -f $_.Exception.Message)
    }
    foreach ($name in @($script:UiTickHandlers.Keys)) {
        try {
            & $script:UiTickHandlers[$name]
        } catch {
            Write-RunLog -Log $script:UiPumpLog -Level ERREUR -Message ("Erreur interface ({0}) : {1}" -f $name, $_.Exception.Message)
        }
    }
    try { Invoke-UiLogDrain } catch { Write-Verbose $_.Exception.Message }
}

function Invoke-UiLogDrain {
    foreach ($entry in (Receive-RunLogEntry -Log $script:UiPumpLog)) {
        if ([string]$entry.Level -eq 'PROGRESS') { Set-RunProgress -Current $entry.Current -Total $entry.Total -Label $entry.Line }
        else { Add-LogLine -Entry $entry }
    }
}

function Invoke-UiBackgroundWorkCheck {
    # .ToArray() et non @(...) : @() sur une List[object] déclenche un bogue du binder de PowerShell 5.1.
    foreach ($pending in $script:UiPendingWorks.ToArray()) {
        if (-not (Test-BackgroundWorkCompleted -Work $pending.Work)) { continue }
        [void]$script:UiPendingWorks.Remove($pending)
        Invoke-UiLogDrain
        $result = $null
        $failure = $null
        try { $result = Receive-BackgroundWork -Work $pending.Work } catch { $failure = $_.Exception.Message }
        try {
            if ($null -eq $failure) { & $pending.OnCompleted $result }
            else { & $pending.OnFailed $failure }
        } catch {
            Write-RunLog -Log $script:UiPumpLog -Level ERREUR -Message ("Erreur interface (fin du travail {0}) : {1}" -f $pending.Work.Name, $_.Exception.Message)
        }
    }
}
