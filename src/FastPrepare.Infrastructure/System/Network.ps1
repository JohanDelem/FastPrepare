<#
    Cartes réseau physiques et test de connexion internet.
    Le test est asynchrone (HttpClient) : l'appelant le démarre puis vient lire le résultat,
    sans jamais bloquer le fil de l'interface. Aucun minuteur ici.
#>

function Get-PhysicalAdapter {
    <# Cartes réseau physiques { Name, Description, Mac, Ipv6Enabled }, triées par nom. #>
    [CmdletBinding()]
    param()

    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Sort-Object -Property Name)) {
        $binding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID 'ms_tcpip6' -ErrorAction SilentlyContinue
        [pscustomobject]@{
            PSTypeName  = 'FastPrepare.NetworkAdapter'
            Name        = [string]$adapter.Name
            Description = [string]$adapter.InterfaceDescription
            Mac         = [string]$adapter.MacAddress
            Ipv6Enabled = [bool]($binding -and $binding.Enabled)
        }
    }
}

function Disable-AdapterIpv6 {
    <#
        Désactive IPv6 (liaison ms_tcpip6) sur une carte réseau, puis vérifie le résultat.
        Sans effet si IPv6 y est déjà désactivé. Renvoie { Changed }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $binding = Get-NetAdapterBinding -Name $Name -ComponentID 'ms_tcpip6' -ErrorAction Stop
    if (-not $binding.Enabled) { return [pscustomobject]@{ Changed = $false } }
    Disable-NetAdapterBinding -Name $Name -ComponentID 'ms_tcpip6' -ErrorAction Stop
    if ((Get-NetAdapterBinding -Name $Name -ComponentID 'ms_tcpip6' -ErrorAction Stop).Enabled) {
        throw "IPv6 toujours actif sur la carte '$Name' après désactivation."
    }
    return [pscustomobject]@{ Changed = $true }
}

function New-ConnectivityProbe {
    <# Prépare une sonde de connexion réutilisable : { Client, Url, Expected, Task }. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    return [pscustomobject]@{
        PSTypeName = 'FastPrepare.ConnectivityProbe'
        Client     = $client
        Url        = $Url
        Expected   = $Expected
        Task       = $null
    }
}

function Start-ConnectivityCheck {
    <# Lance une requête asynchrone (sans effet si une requête est déjà en cours). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Probe)
    if ($null -eq $Probe.Task) {
        $Probe.Task = $Probe.Client.GetStringAsync($Probe.Url)
    }
}

function Read-ConnectivityResult {
    <# 'Pending' tant que la requête est en cours ; sinon 'Ok' ou 'Failed' (et la sonde est prête à relancer). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Probe)

    $task = $Probe.Task
    if ($null -eq $task) { return 'Failed' }
    if (-not $task.IsCompleted) { return 'Pending' }

    $ok = $false
    if ($task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
        $ok = ([string]$task.Result).Contains($Probe.Expected)
    }
    $Probe.Task = $null
    if ($ok) { return 'Ok' }
    return 'Failed'
}

function Close-ConnectivityProbe {
    <# Libère le client HTTP de la sonde. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Probe)
    if ($Probe.Client) { $Probe.Client.Dispose() }
}
