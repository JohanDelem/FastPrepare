<#
    Étape 13 — Changement du nom d'hôte, pris en compte au redémarrage (section 1).
    Le nom est revalidé par Test-HostName (FastPrepare.Core) ; jamais de redémarrage automatique.
#>

Register-Step -Id 'rename-computer' -Section 1 -Title 'Changement du nom d''hôte' -Plan {
    param($Selection, $Snapshot, $Context)
    if (-not $Selection.HostName.Enabled) { return }
    $name = [string]$Selection.HostName.Name
    New-StepAction -Label ("Nom d'hôte : Rename-Computer -NewName '{0}' (pris en compte au redémarrage)" -f $name) -Parameters @{ Kind = 'RenameComputer'; NewName = $name }
} -Invoke {
    param($Action, $Context)
    $name = [string]$Action.Parameters.NewName
    $problem = Get-HostNameError -Name $name
    if ($problem) { throw "nom d'hôte refusé ($problem)" }
    $result = Rename-LocalComputer -NewName $name -Log $Context.Log
    if (-not $result.Changed) { Write-RunLog -Log $Context.Log -Message "Le poste s'appelle déjà '$name'" }
    [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
