<#
    Étape 5 — Désinstallation des logiciels cochés (section 2).
    Silencieux d'abord, assistants en dernier (Get-UninstallOrder, FastPrepare.Core).
#>

Register-Step -Id 'uninstall-software' -Section 2 -Title 'Désinstallation des logiciels' -Plan {
    param($Selection, $Snapshot, $Context)
    foreach ($app in (Get-UninstallOrder -Software @($Selection.Software.Items))) {
        $parameters = @{
            Kind    = 'Uninstall'
            Name    = [string]$app.Name
            Version = [string]$app.Version
            Method  = [string]$app.Method
            Command = [string]$app.Command
            Silent  = [bool]$app.Silent
        }
        if (-not $app.Command) {
            New-PlanWarning -Message ("{0} : aucune commande de désinstallation connue, à retirer à la main." -f $app.Name)
            continue
        }
        if ($app.Silent) {
            New-StepAction -Label ('Désinstallation silencieuse ({0}) : {1} → {2}' -f $app.Method, $app.Name, $app.Command) -Parameters $parameters
        } else {
            New-StepAction -Label ('Désinstallation avec assistant : {0} → {1}' -f $app.Name, $app.Command) -Parameters $parameters -Interactive
        }
    }
} -Invoke {
    param($Action, $Context)
    $p = $Action.Parameters
    if (-not $p.Silent) {
        Write-RunLog -Log $Context.Log -Level ATTN -Message ("Assistant de désinstallation de {0} : suivez-le à l'écran, l'outil attend sa fermeture." -f $p.Name)
    }
    $result = Invoke-UninstallCommand -Command $p.Command -Interactive:(-not $p.Silent) -Log $Context.Log
    # Certains désinstalleurs (NSIS) rendent la main avant d'avoir fini : on vérifie la disparition.
    if (-not (Wait-UninstallEntryRemoval -DisplayName $p.Name -DisplayVersion $p.Version -TimeoutSeconds 120)) {
        throw 'toujours présent dans la liste des programmes après la désinstallation (assistant annulé ?)'
    }
    [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
