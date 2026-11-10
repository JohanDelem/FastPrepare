<#
    Identité matérielle et logicielle du poste.
#>

function Get-MachineIdentity {
    <# Constructeur, modèle, numéro de série, libellé de Windows et nom d'hôte actuel. #>
    [CmdletBinding()]
    param()

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $currentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue

    $osLabel = ('{0} {1}' -f $os.Caption, $currentVersion.DisplayVersion) -replace '^Microsoft\s+', ''
    return [pscustomobject]@{
        PSTypeName   = 'FastPrepare.MachineIdentity'
        Manufacturer = ([string]$cs.Manufacturer).Trim()
        Model        = ([string]$cs.Model).Trim()
        Serial       = ([string]$bios.SerialNumber).Trim()
        OsLabel      = $osLabel.Trim()
        HostName     = $env:COMPUTERNAME
    }
}
