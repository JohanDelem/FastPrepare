<#
    Stratégie de désinstallation (cahier des charges, tableau « Désinstallation silencieuse »).
    Fonctions pures : la lecture du fichier exécutable (sonde NSIS) est faite par
    FastPrepare.Infrastructure et transmise ici sous forme de résultat.
#>

function Get-UninstallMsiProductCode {
    <# GUID MSI d'une entrée de désinstallation (nom de la clé, puis chaîne de désinstallation), ou $null. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Entry)

    $uninstall = [string]$Entry.UninstallString
    $isMsi = ($Entry.WindowsInstaller -eq 1) -or ($uninstall -match '(?i)msiexec')
    if (-not $isMsi) { return $null }
    if ([string]$Entry.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { return [string]$Entry.PSChildName }
    if ($uninstall -match '\{[0-9A-Fa-f-]{36}\}') { return $Matches[0] }
    return $null
}

function Get-UninstallExecutable {
    <# Chemin de l'exécutable d'une chaîne de désinstallation (entre guillemets, ou jusqu'au premier .exe). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][AllowNull()][string]$UninstallString)

    if ([string]::IsNullOrWhiteSpace($UninstallString)) { return $null }
    if ($UninstallString -match '^\s*"([^"]+)"') { return $Matches[1] }
    if ($UninstallString -match '(?i)^\s*(.+?\.exe)') { return $Matches[1] }
    return $null
}

function Get-UninstallProbeTarget {
    <#
        Exécutable à examiner pour décider de la stratégie, ou $null si l'examen est inutile
        (QuietUninstallString fournie, MSI reconnu, ou aucune commande).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Entry)

    if ($Entry.QuietUninstallString) { return $null }
    if (Get-UninstallMsiProductCode -Entry $Entry) { return $null }
    return (Get-UninstallExecutable -UninstallString ([string]$Entry.UninstallString))
}

function Resolve-UninstallStrategy {
    <#
        Détermine la commande de désinstallation et si elle est silencieuse.
        -ExecutableProbe : résultat de Get-ExecutableProbe pour Get-UninstallProbeTarget
        ({ Path, Exists, IsNsis }), ou $null.
        Renvoie { Silent, Method, Command }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Entry,
        $ExecutableProbe
    )

    if ($Entry.QuietUninstallString) {
        return [pscustomobject]@{ Silent = $true; Method = 'QuietUninstallString'; Command = [string]$Entry.QuietUninstallString }
    }

    $productCode = Get-UninstallMsiProductCode -Entry $Entry
    if ($productCode) {
        return [pscustomobject]@{ Silent = $true; Method = 'MSI'; Command = "msiexec.exe /x $productCode /qn /norestart" }
    }

    $uninstall = [string]$Entry.UninstallString
    if ([string]::IsNullOrWhiteSpace($uninstall)) {
        return [pscustomobject]@{ Silent = $false; Method = 'Aucune commande'; Command = $null }
    }

    if ($ExecutableProbe -and $ExecutableProbe.Exists) {
        $exe = [string]$ExecutableProbe.Path
        $leaf = [System.IO.Path]::GetFileName($exe)
        if ($leaf -match '(?i)^unins\d{3}\.exe$') {
            return [pscustomobject]@{ Silent = $true; Method = 'Inno Setup'; Command = "`"$exe`" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART" }
        }
        if ($ExecutableProbe.IsNsis) {
            return [pscustomobject]@{ Silent = $true; Method = 'NSIS'; Command = "`"$exe`" /S" }
        }
    }

    return [pscustomobject]@{ Silent = $false; Method = 'Assistant'; Command = $uninstall }
}

function Get-UninstallOrder {
    <# Silencieux d'abord, assistants en dernier, ordre alphabétique dans chaque groupe (ordre d'exécution n° 5). #>
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Software)

    if (-not $Software) { return @() }
    $silent = @($Software | Where-Object { $_.Silent } | Sort-Object -Property Name)
    $wizard = @($Software | Where-Object { -not $_.Silent } | Sort-Object -Property Name)
    return @($silent + $wizard)
}
