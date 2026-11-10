<#
    Règles d'une entrée du catalogue des logiciels de la section 8 (fonctionnalité F2,
    plan d'architecture §3.3, DEC17). Source unique : appelées par la validation de software.json
    et par le formulaire de l'onglet Réglages. Fonctions pures.

    Entrée : { Id, Label, DefaultChecked, Install }, Install étant
      { Type = 'winget'; Id; Source; Override }  ou
      { Type = 'download'; Url; FileName; Arguments; Sha256; ExpectedSigner }
    (même modèle d'élément que les utilitaires constructeurs de config.json).
#>

$script:SoftwareInstallFields = @{
    winget   = @('Id', 'Source', 'Override')
    download = @('Url', 'FileName', 'Arguments', 'Sha256', 'ExpectedSigner')
}
$script:WingetSources = @('winget', 'msstore')
$script:MaxSoftwareLabelLength = 80

function ConvertTo-SoftwareEntry {
    <#
        Entrée normalisée à partir d'un objet lu dans le JSON ou saisi dans le formulaire :
        toutes les propriétés présentes, textes sans espaces superflus, empreinte en majuscules.
        Install ne garde que les champs de son type (ce qui sera écrit dans software.json).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$InputObject)

    $install = $null
    if ($InputObject -and $InputObject.PSObject.Properties['Install']) { $install = $InputObject.Install }
    $type = (Get-SoftwareText -Object $install -Name 'Type').ToLowerInvariant()

    $normalizedInstall = [ordered]@{ Type = $type }
    $fields = if ($script:SoftwareInstallFields.ContainsKey($type)) { $script:SoftwareInstallFields[$type] } else { @() }
    foreach ($field in $fields) {
        $value = Get-SoftwareText -Object $install -Name $field
        if ($field -eq 'Sha256') { $value = $value.ToUpperInvariant() }
        if ($field -eq 'Source' -and -not $value) { $value = 'winget' }
        $normalizedInstall[$field] = $value
    }

    $defaultChecked = $false
    if ($InputObject -and $InputObject.PSObject.Properties['DefaultChecked']) { $defaultChecked = [bool]$InputObject.DefaultChecked }

    return [pscustomobject][ordered]@{
        Id             = (Get-SoftwareText -Object $InputObject -Name 'Id')
        Label          = (Get-SoftwareText -Object $InputObject -Name 'Label')
        DefaultChecked = $defaultChecked
        Install        = [pscustomobject]$normalizedInstall
    }
}

function Get-SoftwareEntryError {
    <#
        Problèmes d'une entrée normalisée (ConvertTo-SoftwareEntry), chacun préfixé de son champ.
        -ExistingId : identifiants des autres entrées du catalogue (unicité).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Entry,
        [AllowEmptyCollection()][string[]]$ExistingId = @()
    )
    $problems = New-Object System.Collections.Generic.List[string]

    if (-not $Entry.Label) { $problems.Add('Libellé : vide') }
    elseif ($Entry.Label.Length -gt $script:MaxSoftwareLabelLength) { $problems.Add(('Libellé : {0} caractères sur {1} maximum' -f $Entry.Label.Length, $script:MaxSoftwareLabelLength)) }

    if (-not $Entry.Id) { $problems.Add('Identifiant interne : vide') }
    elseif ($Entry.Id -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $problems.Add('Identifiant interne : minuscules, chiffres et tirets uniquement') }
    elseif (@($ExistingId) -contains $Entry.Id) { $problems.Add(("Identifiant interne : '{0}' déjà utilisé par un autre logiciel" -f $Entry.Id)) }

    $install = $Entry.Install
    switch ([string]$install.Type) {
        'winget' {
            if (-not $install.Id) { $problems.Add('Identifiant winget : vide') }
            elseif ($install.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+\-]*$') { $problems.Add('Identifiant winget : lettres, chiffres, point, tiret, + et _ uniquement (ex. 7zip.7zip)') }
            if ($script:WingetSources -notcontains $install.Source) { $problems.Add(("Source winget : '{0}' ou '{1}' attendu" -f $script:WingetSources[0], $script:WingetSources[1])) }
            if ($install.Override -and $install.Override.Contains('"')) { $problems.Add("Options d'installation : guillemet interdit (elles sont passées entre guillemets à --override)") }
        }
        'download' {
            if (-not $install.Url) { $problems.Add('Lien : vide') }
            elseif ($install.Url -notmatch '^https://[^\s/]+\.[^\s/]+(/\S*)?$') { $problems.Add('Lien : lien https:// complet attendu') }
            if (-not $install.FileName) { $problems.Add('Nom du fichier : vide') }
            elseif ($install.FileName -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._()\-]*\.(exe|msi)$') { $problems.Add('Nom du fichier : nom simple terminé par .exe ou .msi, sans dossier') }
            if (-not $install.ExpectedSigner) { $problems.Add('Éditeur attendu : obligatoire (la signature du fichier est vérifiée avant de le lancer)') }
            if ($install.Sha256 -and $install.Sha256 -notmatch '^[0-9A-F]{64}$') { $problems.Add('Empreinte SHA-256 : 64 caractères hexadécimaux, ou vide') }
        }
        default { $problems.Add("Type : « winget » ou « lien direct » attendu") }
    }
    return $problems.ToArray()
}

function New-SoftwareId {
    <# Identifiant interne déduit du libellé (« 7-Zip » → 7-zip), suffixé -2, -3… s'il est pris. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Label,
        [AllowEmptyCollection()][string[]]$ExistingId = @()
    )
    # Accents retirés par décomposition Unicode, puis tout ce qui n'est ni lettre ni chiffre devient tiret.
    $decomposed = ([string]$Label).Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $decomposed.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$builder.Append($char) }
    }
    $base = [regex]::Replace($builder.ToString().ToLowerInvariant(), '[^a-z0-9]+', '-').Trim('-')
    if (-not $base) { $base = 'logiciel' }
    if ($base.Length -gt 40) { $base = $base.Substring(0, 40).TrimEnd('-') }

    $id = $base
    $suffix = 2
    while (@($ExistingId) -contains $id) {
        $id = '{0}-{1}' -f $base, $suffix
        $suffix++
    }
    return $id
}

function Format-SoftwareInstallCommand {
    <# Commande lisible : formulaire de l'onglet Réglages, info-bulle de la section 8, plan et journal. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Entry)
    $install = $Entry.Install
    switch ([string]$install.Type) {
        'winget' {
            $text = 'winget install --id {0} --source {1} --silent' -f $install.Id, $install.Source
            if ($install.Override) { $text += ' --override "{0}"' -f $install.Override }
            return $text
        }
        'download' {
            $run = if ($install.FileName -match '\.msi$') { 'msiexec /i {0} /qn /norestart' -f $install.FileName } else { $install.FileName }
            if ($install.Arguments) { $run += ' ' + $install.Arguments }
            $text = 'téléchargement de {0} → {1}, signature « {2} » vérifiée' -f $install.Url, $run, $install.ExpectedSigner
            if ($install.Sha256) { $text += ', empreinte vérifiée' }
            return $text
        }
        default { return '(type inconnu)' }
    }
}

function Get-SoftwareText {
    <# Valeur texte d'une propriété (chaîne vide si l'objet ou la propriété manque), sans espaces superflus. #>
    param($Object, [string]$Name)
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name] -or $null -eq $Object.$Name) { return '' }
    return ([string]$Object.$Name).Trim()
}
