<#
    Rapport final : bilan, échecs rappelés un par un, redémarrage nécessaire, emplacement du
    journal et de l'inventaire, rappel des actions manuelles, copie vers le dossier de sortie.
#>

function Write-FinalReport {
    <# Écrit le rapport final dans le journal. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [AllowEmptyCollection()][object[]]$Result = @(),
        [Parameter(Mandatory)]$Context
    )

    $log = $Context.Log
    $results = @($Result)
    $failed = @($results | Where-Object { $_.Outcome -eq 'Failed' })
    $skipped = @($results | Where-Object { $_.Outcome -eq 'Skipped' })
    $succeeded = @($results | Where-Object { $_.Outcome -eq 'Succeeded' })

    if ($Context.Mode -eq 'Simulation') {
        Write-RunLog -Log $log -Level OK -Message ('Rapport final — simulation terminée : {0} action(s) prévue(s), aucune modification du poste.' -f $results.Count)
    } else {
        $level = if ($failed.Count -gt 0) { 'ATTN' } else { 'OK' }
        $summary = 'Rapport final — {0} action(s) réussie(s), {1} en échec' -f $succeeded.Count, $failed.Count
        if ($skipped.Count -gt 0) { $summary += (', {0} ignorée(s) (pas encore disponibles en mode réel)' -f $skipped.Count) }
        Write-RunLog -Log $log -Level $level -Message ($summary + '.')
        foreach ($item in $failed) {
            Write-RunLog -Log $log -Level ERREUR -Message ('  Échec : {0}{1} — {2}' -f (Format-ActionPrefix -Action $item.Action -StepCount $Plan.StepCount), $item.Action.Label, $item.Error)
        }
        if (@($results | Where-Object { $_.RebootRequired }).Count -gt 0) {
            Write-RunLog -Log $log -Level ATTN -Message 'Redémarrage nécessaire pour finaliser certaines actions (aucun redémarrage automatique).'
        }
    }

    if ($Plan.InventoryPath) { Write-RunLog -Log $log -Message "Inventaire N/S + MAC : $($Plan.InventoryPath)" }
    Write-RunLog -Log $log -Message "Journal : $($log.FilePath)"
    $reminders = @(Get-ManualReminder -Config $Context.Config)
    if ($reminders.Count -gt 0) {
        Write-RunLog -Log $log -Level ATTN -Message ('À faire à la main : {0}' -f ($reminders -join ' · '))
    }

    # Dossier de sortie inaccessible au démarrage (journal en repli) : nouvel essai de copie (DEC23).
    if ($log.IsFallback) {
        $copy = Copy-RunLogToOutput -Log $log -AdditionalFile @($Plan.InventoryPath)
        if ($copy.Error) {
            Write-RunLog -Log $log -Level ATTN -Message ("Journal et inventaire restés dans {0} (copie vers le dossier de sortie impossible : {1}) : copiez-les à la main." -f $log.Folder, $copy.Error)
        } else {
            Write-RunLog -Log $log -Level OK -Message ("Journal et inventaire copiés dans le dossier de sortie : {0} (les lignes qui suivent ne figurent que dans {1})" -f $copy.Destination, $log.FilePath)
        }
    }
}

function Get-ManualReminder {
    <# Rappels des actions manuelles de config.json (facultatifs) ; liste vide s'il n'y en a pas. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)]$Config)
    if (-not $Config.PSObject.Properties['ManualReminders']) { return @() }
    return @(@($Config.ManualReminders) | Where-Object { $_ })
}
