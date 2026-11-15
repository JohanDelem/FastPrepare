<#
    Étape 9 — Pilotes et BIOS : commande Update des entrées cochées du catalogue qui en portent
    une (outil du constructeur du poste). Le bloc Update est recopié dans l'action.
#>

Register-Step -Id 'update-drivers' -Title 'Mise à jour des pilotes et du BIOS' -Plan {
    param($Selection, $Snapshot, $Context)
    if (-not $Selection.Updates.Drivers) { return }
    $selected = @($Selection.Catalog.Ids)
    foreach ($software in @($Context.SoftwareCatalog)) {
        if ($selected -notcontains $software.Id -or -not $software.Update) { continue }
        $update = $software.Update
        New-StepAction -Label ('Pilotes et BIOS ({0}) : {1} {2}' -f $update.Label, $update.FilePath, $update.Arguments) -Parameters @{ Kind = 'DriverUpdate'; Update = $update }
    }
} -Invoke {
    param($Action, $Context)
    $update = $Action.Parameters.Update
    $path = Find-InstalledExecutable -Path (Expand-ConfigPath -Path ([string]$update.FilePath) -Variables $Context.Paths.Variables)
    $rebootCodes = if (@($update.RebootExitCodes).Count -gt 0) { [int[]]@($update.RebootExitCodes) } else { [int[]]@(3010, 1641) }
    # Pilotes et BIOS : peut être long ; jamais de redémarrage automatique (arguments du catalogue).
    $result = Invoke-ExternalProcess -FilePath $path -ArgumentList ([string]$update.Arguments) -SuccessExitCode ([int[]]@($update.SuccessExitCodes)) -RebootExitCode $rebootCodes `
        -WorkingDirectory (Split-Path -Path $path -Parent) -TimeoutMinutes 180 -Log $Context.Log
    [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
