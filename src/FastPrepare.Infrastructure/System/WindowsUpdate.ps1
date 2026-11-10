<#
    Windows Update (cahier des charges, section 7) : une passe complète par l'API Windows Update
    Agent (Microsoft.Update.Session) — recherche, téléchargement, installation. Jamais de
    redémarrage : le besoin est seulement signalé.
    La session COM est injectable (-Session) : la logique se teste sans toucher au vrai service.
#>

# Codes de résultat de l'API (OperationResultCode).
$script:WuResultCodes = @{ 0 = 'non démarré'; 1 = 'en cours'; 2 = 'réussi'; 3 = 'réussi avec erreurs'; 4 = 'échec'; 5 = 'interrompu' }

function Invoke-WindowsUpdatePass {
    <#
        Recherche les mises à jour non installées et non masquées, accepte leurs contrats, télécharge
        puis installe en mode silencieux forcé (ForceQuiet), journalise chaque mise à jour.
        Aucune mise à jour n'est écartée d'office : constaté sur poste réel, les pilotes se déclarent
        souvent « peut demander une saisie » (CanRequestUserInput) alors qu'ils s'installent sans
        intervention ; une mise à jour qui exigerait vraiment une saisie échoue et est signalée.
        Renvoie { Found, Installed, Failed (titres), RebootRequired, Remaining }.
        Remaining : mises à jour encore disponibles après la passe (une seule passe, question QO3).
    #>
    [CmdletBinding()]
    param(
        $Session,
        [string]$Criteria = 'IsInstalled=0 and IsHidden=0',
        $Log
    )
    if (-not $Session) { $Session = New-Object -ComObject 'Microsoft.Update.Session' }
    $Session.ClientApplicationID = 'FastPrepare'

    $result = [pscustomobject]@{ Found = 0; Installed = 0; Failed = @(); RebootRequired = $false; Remaining = 0 }

    Write-WuLog -Log $Log -Message 'Windows Update : recherche des mises à jour…'
    $updates = @(Get-WuUpdate -Session $Session -Criteria $Criteria)
    $result.Found = $updates.Count
    if ($updates.Count -eq 0) {
        Write-WuLog -Log $Log -Message 'Windows Update : aucune mise à jour disponible'
        return $result
    }

    $toInstall = New-UpdateCollection
    foreach ($update in $updates) {
        if (-not $update.EulaAccepted) { $update.AcceptEula() }
        [void]$toInstall.Add($update)
    }
    if ($toInstall.Count -eq 0) { return $result }

    Write-WuLog -Log $Log -Message ('Windows Update : téléchargement de {0} mise(s) à jour…' -f $toInstall.Count)
    $downloader = $Session.CreateUpdateDownloader()
    $downloader.Updates = $toInstall
    [void]$downloader.Download()

    $downloaded = New-UpdateCollection
    foreach ($update in $toInstall) {
        if ($update.IsDownloaded) { [void]$downloaded.Add($update) }
        else {
            $result.Failed += [string]$update.Title
            Write-WuLog -Log $Log -Level ERREUR -Message ('Windows Update : téléchargement impossible : {0}' -f $update.Title)
        }
    }

    if ($downloaded.Count -gt 0) {
        Write-WuLog -Log $Log -Message ('Windows Update : installation de {0} mise(s) à jour…' -f $downloaded.Count)
        $installer = $Session.CreateUpdateInstaller()
        # Aucune fenêtre ni invite pendant l'installation (IUpdateInstaller2).
        if ($installer.PSObject.Properties['ForceQuiet']) { $installer.ForceQuiet = $true }
        if ($installer.PSObject.Properties['AllowSourcePrompts']) { $installer.AllowSourcePrompts = $false }
        $installer.Updates = $downloaded
        $installation = $installer.Install()
        $index = 0
        foreach ($update in $downloaded) {
            $code = [int]$installation.GetUpdateResult($index).ResultCode
            $meaning = $script:WuResultCodes[$code]
            if ($code -eq 2 -or $code -eq 3) {
                $result.Installed++
                Write-WuLog -Log $Log -Level OK -Message ('Windows Update : {0} ({1})' -f $update.Title, $meaning)
            } else {
                $result.Failed += [string]$update.Title
                Write-WuLog -Log $Log -Level ERREUR -Message ('Windows Update : {0} — {1}' -f $update.Title, $meaning)
            }
            $index++
        }
        $result.RebootRequired = [bool]$installation.RebootRequired
    }

    $result.Remaining = @(Get-WuUpdate -Session $Session -Criteria $Criteria).Count
    return $result
}

function Get-WuUpdate {
    <# Mises à jour correspondant au critère (énumération de la collection COM). #>
    param($Session, [string]$Criteria)
    $searcher = $Session.CreateUpdateSearcher()
    $search = $searcher.Search($Criteria)
    foreach ($update in $search.Updates) { $update }
}

function New-UpdateCollection {
    <#
        Collection de mises à jour de l'API (remplacée par une liste dans les tests).
        -NoEnumerate : sinon PowerShell énumère la collection COM, et une collection vide devient $null.
    #>
    Write-Output -NoEnumerate -InputObject (New-Object -ComObject 'Microsoft.Update.UpdateColl')
}

function Write-WuLog {
    param($Log, [string]$Message, [string]$Level = 'INFO')
    if ($Log) { Write-RunLog -Log $Log -Level $Level -Message $Message }
}
