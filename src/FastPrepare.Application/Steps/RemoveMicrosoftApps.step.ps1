<#
    Étape 3 — Désinstallation des programmes Microsoft : Office, Outlook, OneNote, Teams (section 3).
    Office Click-to-Run et MSI sont retirés par un seul passage d'ODT (XML de New-OdtRemoveXml).
    Outlook classique et OneNote Click-to-Run partent avec la suite (Remove All).
#>

Register-Step -Id 'remove-microsoft-apps' -Section 3 -Title 'Désinstallation des programmes Microsoft' -Plan {
    param($Selection, $Snapshot, $Context)
    $ms = $Selection.MicrosoftApps

    if ($ms.OfficeClickToRun -or $ms.OfficeMsi) {
        $parts = @()
        if ($ms.OfficeClickToRun) { $parts += 'Click-to-Run, toutes éditions et langues' }
        if ($ms.OfficeMsi) { $parts += 'MSI 2010-2016' }
        $label = 'Office : ODT /configure, suppression {0}' -f ($parts -join ' + ')
        if ($ms.OutlookClassic) { $label += ' · Outlook classique retiré avec la suite' }
        $xml = New-OdtRemoveXml -RemoveClickToRun:([bool]$ms.OfficeClickToRun) -RemoveMsi:([bool]$ms.OfficeMsi)
        New-StepAction -Label $label -Details ($xml -split "`r`n") -Parameters @{ Kind = 'OdtRemove'; Xml = $xml }
    } elseif ($ms.OutlookClassic) {
        New-PlanWarning -Message 'Outlook classique coché sans « Office Click-to-Run » ni « Office MSI » : il n''est retiré qu''avec la suite Office, aucune action prévue (question ouverte QO1).'
    }

    if ($ms.OutlookNew) {
        New-StepAction -Label 'Nouvel Outlook : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (Microsoft.OutlookForWindows)' -Parameters @{ Kind = 'AppxRemove'; Package = 'Microsoft.OutlookForWindows' }
    }

    if ($ms.OneNote) {
        New-StepAction -Label 'OneNote : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (Microsoft.Office.OneNote)' -Parameters @{ Kind = 'AppxRemove'; Package = 'Microsoft.Office.OneNote' }
        if (-not $ms.OfficeClickToRun) {
            New-PlanWarning -Message 'OneNote : la version Click-to-Run n''est retirée qu''avec « Office Click-to-Run » (Remove All) ; seule l''application du Store sera retirée.'
        }
    }

    if ($ms.Teams) {
        New-StepAction -Label 'Teams classique : désinstallation MSI de « Teams Machine-Wide Installer »' -Parameters @{ Kind = 'MsiRemoveByName'; DisplayName = 'Teams Machine-Wide Installer' }
        New-StepAction -Label 'Teams classique : suppression du dossier %LocalAppData%\Microsoft\Teams' -Parameters @{ Kind = 'TeamsClassicFolder' }
        New-StepAction -Label 'Nouveau Teams : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (MSTeams)' -Parameters @{ Kind = 'AppxRemove'; Package = 'MSTeams' }
        New-StepAction -Label 'Teams personnel : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (MicrosoftTeams)' -Parameters @{ Kind = 'AppxRemove'; Package = 'MicrosoftTeams' }
    }
}
