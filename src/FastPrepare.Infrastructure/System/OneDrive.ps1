<#
    OneDrive : état du dossier de la session.
#>

function Get-OneDriveFolderInfo {
    <# Dossier OneDrive d'un profil : { Path, Exists, FileCount }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfilePath)

    $path = Join-Path $ProfilePath 'OneDrive'
    $exists = Test-Path -LiteralPath $path -PathType Container
    $count = 0
    if ($exists) {
        $count = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    }
    return [pscustomobject]@{ Path = $path; Exists = $exists; FileCount = $count }
}
