<#
    Nom d'hôte (cahier des charges, section 1). Jamais de redémarrage automatique.
#>

function Rename-LocalComputer {
    <#
        Renomme le poste, pris en compte au prochain redémarrage. Sans effet si le nom est déjà
        celui demandé. Renvoie { Changed, RebootRequired }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$NewName,
        $Log
    )
    if ($NewName -eq $env:COMPUTERNAME) {
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Nom d'hôte déjà '$NewName' : aucun changement" }
        return [pscustomobject]@{ Changed = $false; RebootRequired = $false }
    }
    Rename-Computer -NewName $NewName -Force -ErrorAction Stop -WarningAction SilentlyContinue
    return [pscustomobject]@{ Changed = $true; RebootRequired = $true }
}
