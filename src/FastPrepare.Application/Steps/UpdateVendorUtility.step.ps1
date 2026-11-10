<#
    Étape 11 — MàJ de l'utilitaire constructeur : pilotes, BIOS (section 7).
#>

Register-Step -Id 'update-vendor-utility' -Section 7 -Title 'Mise à jour par l''utilitaire constructeur' -Plan {
    param($Selection, $Snapshot, $Context)
    $key = $Selection.VendorUtility.Key
    if (-not $key -or -not $Selection.Updates.VendorUtility) { return }
    $update = $Context.Config.Utilities.$key.Update
    New-StepAction -Label ('MàJ utilitaire : {0} {1}' -f $update.FilePath, $update.Arguments) -Parameters @{ Kind = 'UtilityUpdate'; UtilityKey = $key }
} -Invoke {
    param($Action, $Context)
    $update = $Context.Config.Utilities.($Action.Parameters.UtilityKey).Update
    $path = Find-InstalledExecutable -Path (Expand-ConfigPath -Path ([string]$update.FilePath) -Variables $Context.Paths.Variables)
    $rebootCodes = if ($update.PSObject.Properties['RebootExitCodes']) { [int[]]@($update.RebootExitCodes) } else { [int[]]@(3010, 1641) }
    # Pilotes et BIOS : peut être long ; jamais de redémarrage automatique (arguments de config.json).
    $result = Invoke-ExternalProcess -FilePath $path -ArgumentList ([string]$update.Arguments) -SuccessExitCode ([int[]]@($update.SuccessExitCodes)) -RebootExitCode $rebootCodes `
        -WorkingDirectory (Split-Path -Path $path -Parent) -TimeoutMinutes 180 -Log $Context.Log
    [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
