<#
    Dossier de travail de l'outil sur le poste (Execution.WorkFolder) : téléchargements et Office
    Deployment Tool. Rien ne doit en rester sur un poste livré (DEC28).
#>

function Remove-WorkSubfolder {
    <#
        Supprime un sous-dossier du dossier de travail, seulement s'il en est un descendant strict
        (Test-SafeChildPath, FastPrepare.Core). Sans effet s'il n'existe pas. Renvoie { Changed }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$WorkFolder
    )
    if (-not (Test-SafeChildPath -Path $Path -Root $WorkFolder)) {
        throw "Suppression refusée par la garde de chemin : $Path n'est pas dans $WorkFolder"
    }
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ Changed = $false } }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    return [pscustomobject]@{ Changed = $true }
}
