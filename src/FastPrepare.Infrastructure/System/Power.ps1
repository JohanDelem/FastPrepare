<#
    Mode d'alimentation (cahier des charges, section 9) : powercfg /change.
#>

function Set-PowerTimeout {
    <#
        Écran éteint après -MonitorMinutes, mise en veille après -StandbyMinutes, sur secteur
        (et sur batterie si -IncludeBattery). Une commande powercfg par réglage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$MonitorMinutes,
        [Parameter(Mandatory)][int]$StandbyMinutes,
        [switch]$IncludeBattery,
        $Log
    )
    $powercfg = Get-SystemExecutablePath -Name 'powercfg.exe'
    foreach ($setting in (Get-PowerTimeoutSetting -MonitorMinutes $MonitorMinutes -StandbyMinutes $StandbyMinutes -IncludeBattery:$IncludeBattery)) {
        [void](Invoke-ExternalProcess -FilePath $powercfg -ArgumentList ('/change {0} {1}' -f $setting.Name, $setting.Minutes) -TimeoutMinutes 2 -Log $Log)
    }
}

function Get-PowerTimeoutSetting {
    <# Réglages powercfg à appliquer : { Name, Minutes }. #>
    [CmdletBinding()]
    param([int]$MonitorMinutes, [int]$StandbyMinutes, [switch]$IncludeBattery)
    [pscustomobject]@{ Name = 'monitor-timeout-ac'; Minutes = $MonitorMinutes }
    if ($IncludeBattery) { [pscustomobject]@{ Name = 'monitor-timeout-dc'; Minutes = $MonitorMinutes } }
    [pscustomobject]@{ Name = 'standby-timeout-ac'; Minutes = $StandbyMinutes }
    if ($IncludeBattery) { [pscustomobject]@{ Name = 'standby-timeout-dc'; Minutes = $StandbyMinutes } }
}
