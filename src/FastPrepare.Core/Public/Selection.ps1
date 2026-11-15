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
        # Entrées cochées du catalogue (software.json), outil du constructeur compris (DEC26).
        Catalog        = [pscustomobject]@{ Ids = @() }
        Office         = [pscustomobject]@{ EditionKey = $null; WithoutTeams = $false; IncludedApps = @() }
        # Drivers : commande Update des entrées cochées qui en portent une (pilotes, BIOS).
        Updates        = [pscustomobject]@{ WindowsUpdate = $false; Drivers = $false }
        SystemSettings = [pscustomobject]@{ Ipv6Adapters = @(); Power = $false }
        # Session à créer. Password : SecureString, jamais une chaîne (DEC15).
        NewLocalAccount = [pscustomobject]@{
            Enabled              = $false
            Name                 = ''
            FullName             = ''
            Password             = $null
            Administrator        = $false
            PasswordNeverExpires = $false
            MustChangePassword   = $false
        }
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
        [Parameter(Mandatory)]$Snapshot,
        # Catalogue des logiciels (software.json).
        [AllowEmptyCollection()][object[]]$SoftwareCatalog = @()
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

    foreach ($problem in @(Get-NewLocalAccountProblem -Selection $Selection -Snapshot $Snapshot)) { $problems.Add($problem) }

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

    # Catalogue : entrée connue, et proposée sur ce constructeur (DEC25 : l'outil d'un autre
    # constructeur n'est jamais installé, même si une sélection le demande).
    $manufacturer = [string]$Snapshot.Identity.Manufacturer
    $hasUpdate = $false
    foreach ($id in @($Selection.Catalog.Ids)) {
        $entry = @($SoftwareCatalog) | Where-Object { [string]$_.Id -eq $id } | Select-Object -First 1
        if (-not $entry) { $problems.Add("Logiciel inconnu du catalogue : '$id'"); continue }
        if (-not (Test-SoftwareApplicable -Entry $entry -Manufacturer $manufacturer)) {
            $problems.Add(("« {0} » est réservé à un autre constructeur que celui du poste ({1})" -f $entry.Label, $(if ($manufacturer) { $manufacturer } else { 'constructeur non détecté' })))
        }
        if ($entry.Update) { $hasUpdate = $true }
    }
    if ($Selection.Updates.Drivers -and -not $hasUpdate) {
        $problems.Add('Mise à jour des pilotes et du BIOS demandée sans outil constructeur coché')
    }

    return $problems.ToArray()
}

function Get-NewLocalAccountProblem {
    <#
        Incohérences de la session à créer : nom refusé (comptes qui existeront encore après les
        suppressions cochées, nom du poste actuel et futur), mot de passe absent ou trop long,
        options d'expiration contradictoires.
    #>
    param($Selection, $Snapshot)
    $account = $Selection.NewLocalAccount
    if (-not $account -or -not $account.Enabled) { return }

    $removed = @(@($Selection.LocalAccounts.Items) | ForEach-Object { [string]$_.Name })
    $existing = @()
    if ($Snapshot.LocalAccounts -and $Snapshot.LocalAccounts.PSObject.Properties['Names']) {
        $existing = @(@($Snapshot.LocalAccounts.Names) | Where-Object { $removed -notcontains $_ })
    }
    $computers = @([string]$Snapshot.Identity.HostName)
    if ($Selection.HostName.Enabled) { $computers += [string]$Selection.HostName.Name }

    $nameError = Get-LocalAccountNameError -Name $account.Name -ExistingName $existing -ComputerName $computers
    if ($nameError) { ("Session à créer : nom refusé ({0})" -f $nameError) }
    $passwordError = Get-LocalAccountPasswordError -Password $account.Password
    if ($passwordError) { ("Session à créer : {0}" -f $passwordError) }
    if ($account.PasswordNeverExpires -and $account.MustChangePassword) {
        "Session à créer : « n'expire jamais » et « à changer à la première ouverture » sont incompatibles"
    }
}

function Clear-SelectionSecret {
    <#
        Libère le mot de passe porté par la sélection (les actions du plan référencent le même
        objet). À appeler dès que la sélection n'est plus utile.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Selection)
    if (-not $Selection -or -not $Selection.PSObject.Properties['NewLocalAccount']) { return }
    $password = $Selection.NewLocalAccount.Password
    if ($password -is [System.Security.SecureString]) { $password.Dispose() }
    $Selection.NewLocalAccount.Password = $null
}
