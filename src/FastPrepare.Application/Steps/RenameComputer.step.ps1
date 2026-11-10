<#
    Étape 13 — Changement du nom d'hôte, pris en compte au redémarrage (section 1).
    Le nom est revalidé par Test-HostName (FastPrepare.Core) ; jamais de redémarrage automatique.
#>

Register-Step -Id 'rename-computer' -Section 1 -Title 'Changement du nom d''hôte' -Plan {
    param($Selection, $Snapshot, $Context)
    if (-not $Selection.HostName.Enabled) { return }
    $name = [string]$Selection.HostName.Name
    New-StepAction -Label ("Nom d'hôte : Rename-Computer -NewName '{0}' (pris en compte au redémarrage)" -f $name) -Parameters @{ Kind = 'RenameComputer'; NewName = $name }
}
