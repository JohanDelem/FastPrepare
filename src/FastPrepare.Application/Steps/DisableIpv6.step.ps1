<#
    Étape 9 — Désactivation d'IPv6 sur les cartes cochées (section 9).
    Une carte dont IPv6 est déjà désactivé ne produit pas d'action.
#>

Register-Step -Id 'disable-ipv6' -Section 9 -Title 'Désactivation d''IPv6' -Plan {
    param($Selection, $Snapshot, $Context)
    foreach ($adapter in @($Selection.SystemSettings.Ipv6Adapters)) {
        if (-not $adapter.Ipv6Enabled) { continue }
        New-StepAction -Label ("IPv6 : Disable-NetAdapterBinding -Name '{0}' -ComponentID ms_tcpip6" -f $adapter.Name) -Parameters @{
            Kind = 'DisableIpv6'; AdapterName = [string]$adapter.Name
        }
    }
}
