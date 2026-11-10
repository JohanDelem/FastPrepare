<#
    Lecture et validation de config.json (version 3 ; le catalogue des logiciels de la section 8
    est dans un fichier à part, software.json, lu par SoftwareCatalog.ps1).
    Une configuration invalide est refusée au démarrage, avec la liste complète des problèmes
    et le chemin de chacun, plutôt que découverte au milieu d'une exécution.
#>

$script:SupportedConfigVersion = 3

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
    if ($Config.ConfigVersion -ne $script:SupportedConfigVersion) {
        throw ("config.json : ConfigVersion $($Config.ConfigVersion) non prise en charge, " +
            "cette version de l'outil attend $script:SupportedConfigVersion.")
    }

    # Execution, Logging
    if (Test-ConfigField $report $Config 'Execution' '' Object) {
        if (Test-ConfigField $report $Config.Execution 'DefaultMode' 'Execution' NonEmptyString) {
            if (@('Simulation', 'Real') -notcontains $Config.Execution.DefaultMode) {
                $report.Errors.Add("Execution.DefaultMode : 'Simulation' ou 'Real' attendu")
            }
        }
        [void](Test-ConfigField $report $Config.Execution 'CacheFolder' 'Execution' NonEmptyString)
    }
    if (Test-ConfigField $report $Config 'Logging' '' Object) {
        [void](Test-ConfigField $report $Config.Logging 'Folder' 'Logging' NonEmptyString)
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
        [void](Test-ConfigField $report $Config.Winget 'OfflineBundle' 'Winget' NonEmptyString)
    }

    # Utilities
    if (Test-ConfigField $report $Config 'Utilities' '' Object) {
        $keys = @($Config.Utilities.PSObject.Properties | ForEach-Object { $_.Name })
        if ($keys.Count -eq 0) { $report.Errors.Add('Utilities : au moins un utilitaire constructeur attendu') }
        foreach ($key in $keys) {
            Test-UtilityConfig -Report $report -Utility $Config.Utilities.$key -Path "Utilities.$key"
        }
    }

    # Office
    if (Test-ConfigField $report $Config 'Office' '' Object) {
        Test-OfficeConfig -Report $report -Office $Config.Office
    }

    # Catalogue des logiciels de la section 8 : fichier à part (itération 9, DEC17).
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

    # ManualReminders
    if (Test-ConfigField $report $Config 'ManualReminders' '' Array) {
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

function Test-UtilityConfig {
    param($Report, $Utility, [string]$Path)

    if (-not ($Utility -is [System.Management.Automation.PSCustomObject])) {
        $Report.Errors.Add("$Path : objet attendu")
        return
    }
    foreach ($name in 'Label', 'Subtitle', 'Tool') {
        [void](Test-ConfigField $Report $Utility $name $Path NonEmptyString)
    }
    [void](Test-ConfigField $Report $Utility 'Logo' $Path String)
    [void](Test-ConfigField $Report $Utility 'ManufacturerPattern' $Path Regex)

    if (Test-ConfigField $Report $Utility 'Install' $Path Array) {
        if (@($Utility.Install).Count -eq 0) { $Report.Errors.Add("$Path.Install : au moins un élément attendu") }
        $i = 0
        foreach ($item in @($Utility.Install)) {
            $itemPath = "$Path.Install[$i]"
            if (Test-ConfigField $Report $item 'Type' $itemPath NonEmptyString) {
                switch ($item.Type) {
                    'winget' {
                        [void](Test-ConfigField $Report $item 'Id' $itemPath NonEmptyString)
                        [void](Test-ConfigField $Report $item 'Source' $itemPath NonEmptyString)
                    }
                    'download' {
                        [void](Test-ConfigField $Report $item 'FileName' $itemPath NonEmptyString)
                        [void](Test-ConfigField $Report $item 'Arguments' $itemPath String)
                        [void](Test-ConfigField $Report $item 'Sha256' $itemPath String -Optional)
                        [void](Test-ConfigField $Report $item 'ExpectedSigner' $itemPath String -Optional)
                        if (Test-ConfigField $Report $item 'Url' $itemPath String) {
                            if (-not $item.Url) { $Report.Warnings.Add("$itemPath.Url : lien à renseigner avant la première installation réelle") }
                            elseif ($item.Url -notmatch '^https://') { $Report.Errors.Add("$itemPath.Url : lien https:// attendu") }
                        }
                    }
                    default { $Report.Errors.Add("$itemPath.Type : 'winget' ou 'download' attendu") }
                }
            }
            $i++
        }
    }

    if (Test-ConfigField $Report $Utility 'Update' $Path Object) {
        [void](Test-ConfigField $Report $Utility.Update 'FilePath' "$Path.Update" NonEmptyString)
        [void](Test-ConfigField $Report $Utility.Update 'Arguments' "$Path.Update" String)
        foreach ($codes in @(@{ Name = 'SuccessExitCodes'; Optional = $false }, @{ Name = 'RebootExitCodes'; Optional = $true })) {
            if (Test-ConfigField $Report $Utility.Update $codes.Name "$Path.Update" Array -Optional:$codes.Optional) {
                foreach ($code in @($Utility.Update.($codes.Name))) {
                    if (-not (($code -is [int]) -or ($code -is [long]))) { $Report.Errors.Add("$Path.Update.$($codes.Name) : entiers attendus") }
                }
            }
        }
    }

    if (Test-ConfigField $Report $Utility 'DotNet' $Path Array -Optional) {
        $i = 0
        foreach ($requirement in @($Utility.DotNet)) {
            $reqPath = "$Path.DotNet[$i]"
            [void](Test-ConfigField $Report $requirement 'DcuVersion' $reqPath Version)
            [void](Test-ConfigField $Report $requirement 'WingetId' $reqPath NonEmptyString)
            [void](Test-ConfigField $Report $requirement 'MinVersion' $reqPath Version)
            if (Test-ConfigField $Report $requirement 'MaxVersion' $reqPath String) {
                if ($requirement.MaxVersion -and -not ($requirement.MaxVersion -as [version])) {
                    $Report.Errors.Add("$reqPath.MaxVersion : numéro de version ou chaîne vide attendu")
                }
            }
            $i++
        }
    }
}

function Test-OfficeConfig {
    param($Report, $Office)

    [void](Test-ConfigField $Report $Office 'OdtSetupUrl' 'Office' HttpsUrl)
    [void](Test-ConfigField $Report $Office 'OdtFolder' 'Office' NonEmptyString)
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
