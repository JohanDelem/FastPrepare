<#
    Règles d'une entrée du catalogue des logiciels (plan d'architecture §3.3, F2, F4, F5 ;
    DEC17, DEC25, DEC26). Source unique : appelées par la validation de software.json, par le
    formulaire de l'onglet Réglages, par la section Installations et par le plan d'exécution.
    Fonctions pures.

    Entrée : { Id, Label, DefaultChecked, ManufacturerPattern, Install, DotNet, Update }
      Install : { Type = 'winget'; Id; Source; Override; Scope }  ou   (Scope : machine, user ou vide)
                { Type = 'download'; Url; FileName; Arguments; Sha256; ExpectedSigner }
      Facultatifs (outils propres à un constructeur, notamment) :
      ManufacturerPattern : expression régulière sur le constructeur du poste ; vide = tous les postes.
      DotNet : @({ ToolVersion; WingetId; MinVersion; MaxVersion }) — runtime .NET Desktop requis
               selon la version de l'outil proposée par winget (entrées winget seulement).
      Update : { Label; FilePath; Arguments; SuccessExitCodes; RebootExitCodes } — commande de mise
               à jour des pilotes et du BIOS, lancée par l'étape update-drivers.
#>

$script:SoftwareInstallFields = @{
    winget   = @('Id', 'Source', 'Override', 'Scope')
    download = @('Url', 'FileName', 'Arguments', 'Sha256', 'ExpectedSigner')
}
$script:WingetSources = @('winget', 'msstore')
# Portée d'installation (DEC22) : vide = choix de winget.
$script:WingetScopes = @('', 'machine', 'user')
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
        if ($field -eq 'Scope') { $value = $value.ToLowerInvariant() }
        if ($field -eq 'Source' -and -not $value) { $value = 'winget' }
        $normalizedInstall[$field] = $value
    }

    $defaultChecked = $false
    if ($InputObject -and $InputObject.PSObject.Properties['DefaultChecked']) { $defaultChecked = [bool]$InputObject.DefaultChecked }

    $label = Get-SoftwareText -Object $InputObject -Name 'Label'
    return [pscustomobject][ordered]@{
        Id                  = (Get-SoftwareText -Object $InputObject -Name 'Id')
        Label               = $label
        DefaultChecked      = $defaultChecked
        ManufacturerPattern = (Get-SoftwareText -Object $InputObject -Name 'ManufacturerPattern')
        Install             = [pscustomobject]$normalizedInstall
        DotNet              = @(ConvertTo-SoftwareDotNetRequirement -InputObject $InputObject)
        Update              = (ConvertTo-SoftwareUpdate -InputObject $InputObject -DefaultLabel $label)
    }
}

function ConvertTo-SoftwareDotNetRequirement {
    <# Liste DotNet normalisée d'une entrée (vide si absente). #>
    param($InputObject)
    if (-not $InputObject -or -not $InputObject.PSObject.Properties['DotNet']) { return }
    foreach ($requirement in @($InputObject.DotNet)) {
        if ($null -eq $requirement) { continue }
        [pscustomobject][ordered]@{
            ToolVersion = (Get-SoftwareText -Object $requirement -Name 'ToolVersion')
            WingetId    = (Get-SoftwareText -Object $requirement -Name 'WingetId')
            MinVersion  = (Get-SoftwareText -Object $requirement -Name 'MinVersion')
            MaxVersion  = (Get-SoftwareText -Object $requirement -Name 'MaxVersion')
        }
    }
}

function ConvertTo-SoftwareUpdate {
    <# Bloc Update normalisé d'une entrée ; $null s'il est absent. Label par défaut : celui de l'entrée. #>
    param($InputObject, [string]$DefaultLabel)
    if (-not $InputObject -or -not $InputObject.PSObject.Properties['Update'] -or $null -eq $InputObject.Update) { return $null }
    $update = $InputObject.Update
    $label = Get-SoftwareText -Object $update -Name 'Label'
    if (-not $label) { $label = $DefaultLabel }
    $codes = @{}
    foreach ($name in 'SuccessExitCodes', 'RebootExitCodes') {
        # Affectation explicite : en 5.1, « $x = if (…) { @() } » donne $null, pas une liste vide.
        $codes[$name] = @()
        if ($update.PSObject.Properties[$name]) { $codes[$name] = @(@($update.$name) | Where-Object { $null -ne $_ }) }
    }
    return [pscustomobject][ordered]@{
        Label            = $label
        FilePath         = (Get-SoftwareText -Object $update -Name 'FilePath')
        Arguments        = (Get-SoftwareText -Object $update -Name 'Arguments')
        SuccessExitCodes = $codes['SuccessExitCodes']
        RebootExitCodes  = $codes['RebootExitCodes']
    }
}

function ConvertTo-SoftwareDocumentEntry {
    <#
        Forme écrite dans software.json : les champs facultatifs vides (ManufacturerPattern, DotNet,
        Update) sont omis, pour qu'une entrée simple reste lisible.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)
    $document = [ordered]@{ Id = $Entry.Id; Label = $Entry.Label; DefaultChecked = [bool]$Entry.DefaultChecked }
    if ($Entry.ManufacturerPattern) { $document.ManufacturerPattern = $Entry.ManufacturerPattern }
    $document.Install = $Entry.Install
    if (@($Entry.DotNet).Count -gt 0) { $document.DotNet = @($Entry.DotNet) }
    if ($Entry.Update) { $document.Update = $Entry.Update }
    return [pscustomobject]$document
}

function Test-SoftwareApplicable {
    <#
        Vrai si l'entrée est proposée sur un poste de ce constructeur (DEC25) : sans motif, sur
        tous les postes ; avec motif, seulement si le constructeur détecté lui correspond
        (insensible à la casse). Constructeur inconnu ou vide : aucune entrée à motif.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]$Entry,
        [AllowNull()][AllowEmptyString()][string]$Manufacturer
    )
    $pattern = [string]$Entry.ManufacturerPattern
    if (-not $pattern) { return $true }
    if ([string]::IsNullOrWhiteSpace($Manufacturer)) { return $false }
    return ($Manufacturer -match $pattern)
}

function Select-ApplicableSoftware {
    <# Entrées du catalogue proposées sur un poste de ce constructeur, dans l'ordre du catalogue. #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Catalog = @(),
        [AllowNull()][AllowEmptyString()][string]$Manufacturer
    )
    foreach ($entry in @($Catalog)) {
        if (Test-SoftwareApplicable -Entry $entry -Manufacturer $Manufacturer) { $entry }
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
            if ($script:WingetScopes -notcontains $install.Scope) { $problems.Add("Portée : « machine », « user » ou vide attendu") }
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

    if ($Entry.ManufacturerPattern) {
        try { [void][regex]::new($Entry.ManufacturerPattern) } catch { $problems.Add('Constructeur : expression régulière invalide (ex. Dell, ou HP|Hewlett)') }
    }

    $requirements = @($Entry.DotNet)
    if ($requirements.Count -gt 0 -and [string]$install.Type -ne 'winget') {
        $problems.Add("DotNet : réservé aux paquets winget (la version de l'outil est lue dans winget)")
    }
    for ($i = 0; $i -lt $requirements.Count; $i++) {
        $requirement = $requirements[$i]
        if (-not ($requirement.ToolVersion -as [version])) { $problems.Add("DotNet[$i].ToolVersion : numéro de version attendu (ex. 5.7.0)") }
        if (-not $requirement.WingetId) { $problems.Add("DotNet[$i].WingetId : vide") }
        if (-not ($requirement.MinVersion -as [version])) { $problems.Add("DotNet[$i].MinVersion : numéro de version attendu (ex. 8.0.8)") }
        if ($requirement.MaxVersion -and -not ($requirement.MaxVersion -as [version])) { $problems.Add("DotNet[$i].MaxVersion : numéro de version ou vide attendu") }
    }

    if ($Entry.Update) {
        if (-not $Entry.Update.FilePath) { $problems.Add('Update.FilePath : vide') }
        if (@($Entry.Update.SuccessExitCodes).Count -eq 0) { $problems.Add('Update.SuccessExitCodes : au moins un code de sortie attendu') }
        foreach ($name in 'SuccessExitCodes', 'RebootExitCodes') {
            foreach ($code in @($Entry.Update.$name)) {
                if (-not (($code -is [int]) -or ($code -is [long]))) { $problems.Add("Update.$name : entiers attendus"); break }
            }
        }
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
    <# Commande lisible : formulaire de l'onglet Réglages, info-bulle de la section Installations, plan et journal. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Entry)
    $install = $Entry.Install
    switch ([string]$install.Type) {
        'winget' {
            $text = 'winget install --id {0} --source {1}' -f $install.Id, $install.Source
            if ($install.Scope) { $text += ' --scope {0}' -f $install.Scope }
            $text += ' --silent'
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
