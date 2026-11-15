<#
    Lecture et validation de config.json (version 4 ; le catalogue des logiciels est dans un
    fichier à part, software.json, lu par SoftwareCatalog.ps1).
    Une configuration invalide est refusée au démarrage, avec la liste complète des problèmes
    et le chemin de chacun, plutôt que découverte au milieu d'une exécution.
#>

$script:SupportedConfigVersion = 4

function Read-AppConfig {
    <# Lit config.json (UTF-8) et le valide. Renvoie { Config, Warnings, Path }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "config.json introuvable : $Path"
    }
    try {
        $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "config.json n'est pas un JSON valide ($Path) : $($_.Exception.Message)"
    }
    $warnings = Assert-AppConfig -Config $config
    return [pscustomobject]@{ Config = $config; Warnings = @($warnings); Path = $Path }
}

function Assert-AppConfig {
    <#
        Vérifie le format de la configuration. Lève une erreur unique qui liste tous les problèmes
        bloquants ; renvoie les avertissements non bloquants (valeurs à compléter plus tard).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)]$Config)

    $report = [pscustomobject]@{
        Errors   = New-Object System.Collections.Generic.List[string]
        Warnings = New-Object System.Collections.Generic.List[string]
    }

    if (-not $Config.PSObject.Properties['ConfigVersion']) {
        throw ("config.json : format non reconnu (clé 'ConfigVersion' absente). " +
            "Cette version de l'outil attend 'ConfigVersion': $script:SupportedConfigVersion.")
    }
    if ($Config.ConfigVersion -eq 2) {
        throw ("config.json : ConfigVersion 2 n'est plus prise en charge. Passez 'ConfigVersion' à 3, " +
            "déplacez la liste 'Software' dans software.json (format : docs/architecture_plan.md, C11) " +
            'et ajoutez "SoftwareCatalog": "software.json".')
    }
    if ($Config.ConfigVersion -eq 3) {
        throw ("config.json : ConfigVersion 3 n'est plus prise en charge. Passez 'ConfigVersion' à 4, " +
            "remplacez 'Logging' par 'Output' (dossier de sortie), 'Execution.CacheFolder' par 'Execution.WorkFolder' " +
            "retirez 'Office.OdtFolder' et déplacez 'Utilities' dans software.json (format : docs/architecture_plan.md, C12 à C15).")
    }
    if ($Config.ConfigVersion -ne $script:SupportedConfigVersion) {
        throw ("config.json : ConfigVersion $($Config.ConfigVersion) non prise en charge, " +
            "cette version de l'outil attend $script:SupportedConfigVersion.")
    }

    # Execution, Output
    if (Test-ConfigField $report $Config 'Execution' '' Object) {
        if (Test-ConfigField $report $Config.Execution 'DefaultMode' 'Execution' NonEmptyString) {
            if (@('Simulation', 'Real') -notcontains $Config.Execution.DefaultMode) {
                $report.Errors.Add("Execution.DefaultMode : 'Simulation' ou 'Real' attendu")
            }
        }
        [void](Test-ConfigField $report $Config.Execution 'WorkFolder' 'Execution' NonEmptyString)
    }
    # Dossier de sortie (journal, inventaire) : relatif au dossier de l'outil, absolu ou réseau.
    if (Test-ConfigField $report $Config 'Output' '' Object) {
        [void](Test-ConfigField $report $Config.Output 'Folder' 'Output' NonEmptyString)
    }

    # Connectivity
    if (Test-ConfigField $report $Config 'Connectivity' '' Object) {
        $c = $Config.Connectivity
        [void](Test-ConfigField $report $c 'TestUrl' 'Connectivity' Url)
        [void](Test-ConfigField $report $c 'Expected' 'Connectivity' NonEmptyString)
        foreach ($name in 'IntervalSeconds', 'TimeoutSeconds', 'RetrySeconds') {
            [void](Test-ConfigField $report $c $name 'Connectivity' PositiveInt)
        }
    }

    # Winget
    if (Test-ConfigField $report $Config 'Winget' '' Object) {
        [void](Test-ConfigField $report $Config.Winget 'FamilyName' 'Winget' NonEmptyString)
        # Paquet winget hors ligne : facultatif, chemin relatif au dossier de l'outil.
        [void](Test-ConfigField $report $Config.Winget 'OfflineBundle' 'Winget' NonEmptyString -Optional)
        # Paquet de données de la source winget (itération 11) : facultatif, réparation automatique.
        if (Test-ConfigField $report $Config.Winget 'SourcePackage' 'Winget' Object -Optional) {
            [void](Test-ConfigField $report $Config.Winget.SourcePackage 'Url' 'Winget.SourcePackage' HttpsUrl)
            [void](Test-ConfigField $report $Config.Winget.SourcePackage 'ExpectedSigner' 'Winget.SourcePackage' NonEmptyString)
        }
    }

    # Outils constructeurs : entrées de software.json depuis l'itération 13 (DEC26).
    if ($Config.PSObject.Properties['Utilities']) {
        $report.Errors.Add("Utilities : les outils constructeurs sont désormais des entrées de software.json (champ 'ManufacturerPattern' ; format : docs/architecture_plan.md, C13)")
    }

    # Office
    if (Test-ConfigField $report $Config 'Office' '' Object) {
        Test-OfficeConfig -Report $report -Office $Config.Office
    }

    # Catalogue des logiciels : fichier à part (DEC17).
    [void](Test-ConfigField $report $Config 'SoftwareCatalog' '' NonEmptyString)
    if ($Config.PSObject.Properties['Software']) {
        $report.Errors.Add("Software : la liste des logiciels est désormais dans le fichier désigné par 'SoftwareCatalog' (software.json)")
    }

    # Power
    if (Test-ConfigField $report $Config 'Power' '' Object) {
        [void](Test-ConfigField $report $Config.Power 'MonitorTimeoutMinutes' 'Power' PositiveInt)
        [void](Test-ConfigField $report $Config.Power 'StandbyTimeoutMinutes' 'Power' PositiveInt)
        [void](Test-ConfigField $report $Config.Power 'ApplyOnBattery' 'Power' Bool)
    }

    # NewLocalAccount (facultatif, itération 8) : valeurs par défaut des cases de la section 11.
    if (Test-ConfigField $report $Config 'NewLocalAccount' '' Object -Optional) {
        $account = $Config.NewLocalAccount
        $neverExpires = Test-ConfigField $report $account 'PasswordNeverExpires' 'NewLocalAccount' Bool -Optional
        $mustChange = Test-ConfigField $report $account 'MustChangePassword' 'NewLocalAccount' Bool -Optional
        [void](Test-ConfigField $report $account 'Administrator' 'NewLocalAccount' Bool -Optional)
        if ($neverExpires -and $mustChange -and $account.PasswordNeverExpires -and $account.MustChangePassword) {
            $report.Errors.Add('NewLocalAccount : PasswordNeverExpires et MustChangePassword ne peuvent pas être vrais ensemble')
        }
    }

    # ManualReminders (facultatif : sans rappel, le mémo n'est pas affiché)
    if (Test-ConfigField $report $Config 'ManualReminders' '' Array -Optional) {
        $i = 0
        foreach ($reminder in @($Config.ManualReminders)) {
            if (-not ($reminder -is [string]) -or -not $reminder.Trim()) { $report.Errors.Add("ManualReminders[$i] : texte attendu") }
            $i++
        }
    }

    if ($report.Errors.Count -gt 0) {
        throw ("config.json invalide :`n- " + ($report.Errors -join "`n- "))
    }
    return $report.Warnings.ToArray()
}

function Test-OfficeConfig {
    param($Report, $Office)

    [void](Test-ConfigField $Report $Office 'OdtSetupUrl' 'Office' HttpsUrl)
    if ($Office.PSObject.Properties['OdtFolder']) {
        $Report.Errors.Add("Office.OdtFolder : à retirer, le dossier ODT est désormais dans 'Execution.WorkFolder'")
    }
    if (Test-ConfigField $Report $Office 'Architecture' 'Office' NonEmptyString) {
        if (@('32', '64') -notcontains $Office.Architecture) { $Report.Errors.Add("Office.Architecture : '32' ou '64' attendu") }
    }
    [void](Test-ConfigField $Report $Office 'Language' 'Office' NonEmptyString)

    if (Test-ConfigField $Report $Office 'Editions' 'Office' Array) {
        if (@($Office.Editions).Count -eq 0) { $Report.Errors.Add('Office.Editions : au moins une édition attendue') }
        $keys = @{}
        $i = 0
        foreach ($edition in @($Office.Editions)) {
            $path = "Office.Editions[$i]"
            if (Test-ConfigField $Report $edition 'Key' $path NonEmptyString) {
                if ($keys.ContainsKey($edition.Key)) { $Report.Errors.Add("$path.Key : '$($edition.Key)' en double") }
                $keys[$edition.Key] = $true
            }
            foreach ($name in 'Label', 'Name', 'ProductId', 'Channel') {
                [void](Test-ConfigField $Report $edition $name $path NonEmptyString)
            }
            [void](Test-ConfigField $Report $edition 'NoTeamsProductId' $path String -Optional)
            $i++
        }
    }

    if (Test-ConfigField $Report $Office 'OptionalApps' 'Office' Array) {
        $i = 0
        foreach ($app in @($Office.OptionalApps)) {
            [void](Test-ConfigField $Report $app 'Id' "Office.OptionalApps[$i]" NonEmptyString)
            [void](Test-ConfigField $Report $app 'Label' "Office.OptionalApps[$i]" NonEmptyString)
            $i++
        }
    }
}

function Test-ConfigField {
    <#
        Vérifie qu'une propriété existe et a le type attendu ; ajoute l'erreur au rapport sinon.
        Renvoie vrai si la valeur est utilisable (pour enchaîner les vérifications des enfants).
    #>
    param(
        $Report,
        $Parent,
        [string]$Name,
        [string]$Path,
        [ValidateSet('String', 'NonEmptyString', 'PositiveInt', 'Bool', 'Array', 'Object', 'Version', 'Regex', 'Url', 'HttpsUrl')]
        [string]$Kind,
        [switch]$Optional
    )

    $fullPath = if ($Path) { "$Path.$Name" } else { $Name }
    $isObject = $Parent -is [System.Management.Automation.PSCustomObject]
    if (-not $isObject -or -not $Parent.PSObject.Properties[$Name]) {
        if (-not $Optional) { $Report.Errors.Add("$fullPath : absent") }
        return $false
    }

    $value = $Parent.$Name
    $isString = $value -is [string]
    $problem = switch ($Kind) {
        'String' { if (-not $isString) { 'texte attendu' } }
        'NonEmptyString' { if (-not $isString -or -not $value.Trim()) { 'texte non vide attendu' } }
        'PositiveInt' { if (-not (($value -is [int]) -or ($value -is [long])) -or $value -le 0) { 'entier strictement positif attendu' } }
        'Bool' { if (-not ($value -is [bool])) { 'true ou false attendu' } }
        'Array' { if (-not ($value -is [array])) { 'liste attendue' } }
        'Object' { if (-not ($value -is [System.Management.Automation.PSCustomObject])) { 'objet attendu' } }
        'Version' { if (-not $isString -or -not ($value -as [version])) { 'numéro de version attendu (ex. 8.0.25)' } }
        'Regex' {
            if (-not $isString -or -not $value) { 'expression régulière attendue' }
            else {
                try { [void][regex]::new($value) } catch { 'expression régulière invalide' }
            }
        }
        'Url' { if (-not $isString -or $value -notmatch '^https?://\S+$') { 'lien http:// ou https:// attendu' } }
        'HttpsUrl' { if (-not $isString -or $value -notmatch '^https://\S+$') { 'lien https:// attendu' } }
    }
    if ($problem) {
        $Report.Errors.Add("$fullPath : $problem")
        return $false
    }
    return $true
}
