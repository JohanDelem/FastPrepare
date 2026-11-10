<#
    Étape 10 — Mode d'alimentation (section 9). Durées et batterie issues de config.Power.
#>

Register-Step -Id 'set-power-plan' -Section 9 -Title 'Mode d''alimentation' -Plan {
    param($Selection, $Snapshot, $Context)
    if (-not $Selection.SystemSettings.Power) { return }
    $power = $Context.Config.Power
    $m = $power.MonitorTimeoutMinutes
    $s = $power.StandbyTimeoutMinutes
    $settings = @("monitor-timeout-ac $m", "standby-timeout-ac $s")
    if ($power.ApplyOnBattery) { $settings = @("monitor-timeout-ac $m", "monitor-timeout-dc $m", "standby-timeout-ac $s", "standby-timeout-dc $s") }
    New-StepAction -Label ('Alimentation : powercfg /change {0}' -f ($settings -join ', ')) -Parameters @{
        Kind = 'PowerTimeouts'; MonitorMinutes = [int]$m; StandbyMinutes = [int]$s; IncludeBattery = [bool]$power.ApplyOnBattery
    }
} -Invoke {
    param($Action, $Context)
    $p = $Action.Parameters
    Set-PowerTimeout -MonitorMinutes $p.MonitorMinutes -StandbyMinutes $p.StandbyMinutes -IncludeBattery:([bool]$p.IncludeBattery) -Log $Context.Log
}
