<#
    Schéma de ce que le technicien a coché : contrat entre l'interface et le moteur.
    Chaque section d'interface écrit sa propre partie ; le moteur ne lit que cet objet,
    jamais les contrôles WPF. Fonction pure.
#>

function New-Selection {
    <# Sélection vide (rien n'est coché). #>
    [CmdletBinding()]
    param()

    $selection = [pscustomobject]@{
        PSTypeName     = 'FastPrepare.Selection'
        HostName       = [pscustomobject]@{ Enabled = $false; Name = '' }
        Software       = [pscustomobject]@{ Items = @() }
        MicrosoftApps  = [pscustomobject]@{
            OfficeClickToRun = $false
            OfficeMsi        = $false
            OutlookClassic   = $false
            OutlookNew       = $false
            OneNote          = $false
            Teams            = $false
            OneDrive         = $false
            OneDriveFolder   = $false
        }
        LocalAccounts  = [pscustomobject]@{ Items = @() }
        VendorUtility  = [pscustomobject]@{ Key = $null }
        Office         = [pscustomobject]@{ EditionKey = $null; WithoutTeams = $false; IncludedApps = @() }
        Updates        = [pscustomobject]@{ WindowsUpdate = $false; VendorUtility = $false }
        ExtraSoftware  = [pscustomobject]@{ Ids = @() }
        SystemSettings = [pscustomobject]@{ Ipv6Adapters = @(); Power = $false }
    }
    return $selection
}

function Test-Selection {
    <#
        Cohérence d'une sélection avec la configuration et le relevé du poste. Renvoie la liste des
        incohérences (vide si tout va bien). Défense en profondeur : l'interface ne devrait pas
        permettre ces cas, le plan d'exécution refuse de se construire s'ils se présentent.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Selection,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Snapshot
    )

    $problems = New-Object System.Collections.Generic.List[string]

    if ($Selection.HostName.Enabled -and -not (Test-HostName -Name $Selection.HostName.Name)) {
        $problems.Add(("Nom d'hôte invalide : '{0}'" -f $Selection.HostName.Name))
    }

    if ($Selection.MicrosoftApps.OneDriveFolder -and -not $Selection.MicrosoftApps.OneDrive) {
        $problems.Add('Suppression du dossier OneDrive demandée sans la désinstallation de OneDrive')
    }

    $removableSids = @(@($Snapshot.LocalAccounts.Removable) | ForEach-Object { [string]$_.Sid })
    foreach ($account in @($Selection.LocalAccounts.Items)) {
        if ($removableSids -notcontains [string]$account.Sid) {
            $problems.Add(("Session locale '{0}' absente des comptes supprimables" -f $account.Name))
        }
    }

    $utilityKey = $Selection.VendorUtility.Key
    if ($utilityKey -and -not $Config.Utilities.PSObject.Properties[$utilityKey]) {
        $problems.Add("Utilitaire constructeur inconnu : '$utilityKey'")
    }
    if ($Selection.Updates.VendorUtility -and -not $utilityKey) {
        $problems.Add("Mise à jour de l'utilitaire constructeur demandée sans utilitaire choisi")
    }

    $editionKey = $Selection.Office.EditionKey
    if ($editionKey) {
        $edition = @($Config.Office.Editions) | Where-Object { $_.Key -eq $editionKey } | Select-Object -First 1
        if (-not $edition) { $problems.Add("Édition Office inconnue : '$editionKey'") }
        elseif ($Selection.Office.WithoutTeams -and -not (Test-OfficeEditionHasNoTeamsVariant -Edition $edition)) {
            $problems.Add("L'édition '$editionKey' ne propose pas de variante sans Teams")
        }
        $knownApps = @(@($Config.Office.OptionalApps) | ForEach-Object { [string]$_.Id })
        foreach ($app in @($Selection.Office.IncludedApps)) {
            if ($knownApps -notcontains $app) { $problems.Add("Application Office facultative inconnue : '$app'") }
        }
    }

    $knownSoftware = @(@($Config.Software) | ForEach-Object { [string]$_.Id })
    foreach ($id in @($Selection.ExtraSoftware.Ids)) {
        if ($knownSoftware -notcontains $id) { $problems.Add("Logiciel inconnu (section 8) : '$id'") }
    }

    return $problems.ToArray()
}
