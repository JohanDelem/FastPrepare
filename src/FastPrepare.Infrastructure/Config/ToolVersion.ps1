<#
    Version de l'outil : fichier VERSION à la racine (une ligne, ex. 1.13.0), affichée dans la
    fenêtre et en tête du journal (DEC24).
#>

function Read-ToolVersion {
    <# Version lue dans -Path ; chaîne vide si le fichier est absent ou illisible. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    try {
        $line = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop) | Select-Object -First 1
        return ([string]$line).Trim()
    } catch {
        return ''
    }
}
