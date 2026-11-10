<#
    Étape 5 — Désinstallation des logiciels cochés (section 2).
    Silencieux d'abord, assistants en dernier (Get-UninstallOrder, FastPrepare.Core).
#>

Register-Step -Id 'uninstall-software' -Section 2 -Title 'Désinstallation des logiciels' -Plan {
    param($Selection, $Snapshot, $Context)
    foreach ($app in (Get-UninstallOrder -Software @($Selection.Software.Items))) {
        $parameters = @{ Kind = 'Uninstall'; Name = [string]$app.Name; Method = [string]$app.Method; Command = [string]$app.Command }
        if ($app.Silent) {
            New-StepAction -Label ('Désinstallation silencieuse ({0}) : {1} → {2}' -f $app.Method, $app.Name, $app.Command) -Parameters $parameters
        } else {
            New-StepAction -Label ('Désinstallation avec assistant : {0} → {1}' -f $app.Name, $app.Command) -Parameters $parameters -Interactive
        }
    }
}
