<#
    Lecture des logiciels installés, comme le Panneau de configuration. Aucune décision ici :
    la stratégie de désinstallation est choisie par FastPrepare.Core (Resolve-UninstallStrategy).
#>

$script:UninstallRegistryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

# La signature « Nullsoft » figure dans l'en-tête de l'exécutable NSIS : inutile de lire le fichier entier.
$script:NsisProbeBytes = 512KB

function Get-UninstallEntry {
    <#
        Entrées de désinstallation visibles par l'utilisateur, dédoublonnées par nom + version :
        sans composants système, mises à jour, correctifs ni sous-composants.
    #>
    [CmdletBinding()]
    param()

    $seen = @{}
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($entry in (Get-ItemProperty -Path $script:UninstallRegistryPaths -ErrorAction SilentlyContinue)) {
        if (-not $entry.DisplayName) { continue }
        if ($entry.SystemComponent -eq 1) { continue }
        if ($entry.ParentKeyName -or $entry.ParentDisplayName) { continue }
        if ($entry.ReleaseType -match 'Update|Hotfix') { continue }
        $key = '{0}|{1}' -f $entry.DisplayName, $entry.DisplayVersion
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $entries.Add($entry)
    }
    return $entries.ToArray()
}

function Get-ExecutableProbe {
    <# Examine un désinstalleur : { Path, Exists, IsNsis }. Ne lit que l'en-tête du fichier. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $result = [pscustomobject]@{ Path = $Path; Exists = $false; IsNsis = $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    $result.Exists = $true

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $length = [int][Math]::Min($stream.Length, $script:NsisProbeBytes)
        $buffer = New-Object byte[] $length
        $read = $stream.Read($buffer, 0, $length)
        $text = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
        $result.IsNsis = ($text.IndexOf('Nullsoft', [System.StringComparison]::Ordinal) -ge 0)
    } catch {
        $result.IsNsis = $false
    } finally {
        if ($stream) { $stream.Dispose() }
    }
    return $result
}

function Get-MsiProductCodeByName {
    <# Codes produit MSI des entrées de désinstallation dont le nom affiché est exactement -DisplayName. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$DisplayName)
    $codes = foreach ($entry in (Get-ItemProperty -Path $script:UninstallRegistryPaths -ErrorAction SilentlyContinue)) {
        if ([string]$entry.DisplayName -ne $DisplayName) { continue }
        $code = Get-UninstallMsiProductCode -Entry $entry
        if ($code) { $code }
    }
    return @($codes | Sort-Object -Unique)
}

function Uninstall-MsiProduct {
    <# msiexec /x {GUID} /qn /norestart ; produit déjà absent (1605) = succès. Renvoie { RebootRequired }. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^\{[0-9A-Fa-f-]{36}\}$')][string]$ProductCode,
        $Log
    )
    $result = Invoke-ExternalProcess -FilePath (Get-SystemExecutablePath -Name 'msiexec.exe') -ArgumentList ('/x {0} /qn /norestart' -f $ProductCode) `
        -SuccessExitCode 0, 1605 -TimeoutMinutes 60 -Log $Log
    return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}

function Invoke-UninstallCommand {
    <#
        Exécute la commande de désinstallation choisie par Resolve-UninstallStrategy (FastPrepare.Core).
        msiexec est toujours pris dans System32 ; une commande non analysable passe par cmd.exe /c
        (tracé, décision DEC8). -Interactive : l'assistant de l'application est affiché et attendu.
        Renvoie { RebootRequired }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$Interactive,
        $Log
    )
    $timeout = if ($Interactive) { 120 } else { 60 }
    try {
        $parsed = Split-CommandLine -CommandLine $Command
    } catch {
        $result = Invoke-CmdLine -CommandLine $Command -Interactive:$Interactive -TimeoutMinutes $timeout -Log $Log
        return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
    }

    $filePath = $parsed.FilePath
    $successCodes = @(0)
    if ([System.IO.Path]::GetFileName($filePath) -match '^(?i)msiexec(\.exe)?$') {
        $filePath = Get-SystemExecutablePath -Name 'msiexec.exe'
        $successCodes = @(0, 1605)
    }
    $result = Invoke-ExternalProcess -FilePath $filePath -ArgumentList $parsed.Arguments -SuccessExitCode $successCodes -Interactive:$Interactive -TimeoutMinutes $timeout -Log $Log
    return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}

function Wait-UninstallEntryRemoval {
    <#
        Attend que le logiciel disparaisse de la liste des programmes installés (certains
        désinstalleurs, NSIS notamment, rendent la main avant d'avoir fini). Vrai s'il a disparu.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [AllowEmptyString()][string]$DisplayVersion = '',
        [int]$TimeoutSeconds = 120,
        [int]$PollSeconds = 2
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $present = @(Get-UninstallEntry | Where-Object { $_.DisplayName -eq $DisplayName -and (-not $DisplayVersion -or [string]$_.DisplayVersion -eq $DisplayVersion) })
        if ($present.Count -eq 0) { return $true }
        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Seconds $PollSeconds
    } while ($true)
}
