<#
    Comptes locaux que l'outil ne supprime jamais (cahier des charges, section 4) :
    Administrateur intégré (RID 500), Invité (501), DefaultAccount (503),
    WDAGUtilityAccount (504) et le compte connecté. Fonctions pures.
#>

function Get-ProtectedAccountReason {
    <# Motif de protection d'un compte, ou $null s'il peut être supprimé. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Sid,
        [Parameter(Mandatory)][string]$CurrentSid
    )
    if ($Sid -eq $CurrentSid) { return 'connecté' }
    if ($Sid -match '-(500|501|503|504)$') { return 'intégré' }
    return $null
}

function Test-ProtectedAccount {
    <# Vrai si le compte ne doit jamais être supprimé. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Sid,
        [Parameter(Mandatory)][string]$CurrentSid
    )
    return ($null -ne (Get-ProtectedAccountReason -Sid $Sid -CurrentSid $CurrentSid))
}

function Split-LocalAccount {
    <#
        Sépare les comptes locaux ({ Name, Sid, ProfilePath }) en supprimables et exclus.
        Renvoie { Removable = comptes ; Excluded = libellés « nom » ou « nom (connecté) » }.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Account,
        [Parameter(Mandatory)][string]$CurrentSid
    )

    $removable = New-Object System.Collections.Generic.List[object]
    $excluded = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($Account)) {
        if ($null -eq $a) { continue }
        $reason = Get-ProtectedAccountReason -Sid ([string]$a.Sid) -CurrentSid $CurrentSid
        if ($reason -eq 'connecté') { $excluded.Add(('{0} (connecté)' -f $a.Name)) }
        elseif ($reason) { $excluded.Add([string]$a.Name) }
        else { $removable.Add($a) }
    }
    return [pscustomobject]@{ Removable = $removable.ToArray(); Excluded = $excluded.ToArray() }
}
