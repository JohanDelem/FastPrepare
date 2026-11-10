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
