<#
    Pompe de l'interface : le seul DispatcherTimer de l'application.
    À chaque battement, elle vide la file du journal vers la vue et appelle les traitements
    périodiques enregistrés (test de connexion ; fin des travaux d'arrière-plan à partir de
    l'itération 1). Une erreur dans un traitement est journalisée, jamais propagée.
#>

$script:UiPumpTimer = $null
$script:UiPumpLog = $null
$script:UiTickHandlers = [ordered]@{}

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
    if ($script:UiPumpLog) { Invoke-UiLogDrain }
}

function Invoke-UiPumpTick {
    foreach ($name in @($script:UiTickHandlers.Keys)) {
        try {
            & $script:UiTickHandlers[$name]
        } catch {
            Write-RunLog -Log $script:UiPumpLog -Level ERREUR -Message ("Erreur interface ({0}) : {1}" -f $name, $_.Exception.Message)
        }
    }
    Invoke-UiLogDrain
}

function Invoke-UiLogDrain {
    foreach ($entry in (Receive-RunLogEntry -Log $script:UiPumpLog)) { Add-LogLine -Entry $entry }
}
