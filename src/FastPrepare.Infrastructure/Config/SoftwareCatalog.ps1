<#
    Le fichier software.json : catalogue des logiciels de la section 8 (itération 9, DEC17).
    Contrairement à config.json, il est réécrit par l'outil (onglet Réglages) : écriture atomique,
    ancienne version gardée en .bak. Les règles d'une entrée sont dans FastPrepare.Core
    (SoftwareCatalog.ps1) ; ce fichier ne fait que lire, valider le format et écrire.
#>

$script:SupportedCatalogVersion = 1

function Read-SoftwareCatalog {
    <#
        Lit et valide le catalogue. Fichier absent : catalogue vide et avertissement (la section 8
        est simplement vide). JSON invalide ou entrée refusée : erreur, comme pour config.json.
        Renvoie { Entries (normalisées), Path, Warnings }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Entries = @(); Path = $Path; Warnings = @("Catalogue des logiciels introuvable ($Path) : section 8 vide, ajoutez des logiciels dans l'onglet Réglages") }
    }
    try {
        $catalog = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        throw "software.json n'est pas un JSON valide ($Path) : $($_.Exception.Message)"
    }
    $entries = Assert-SoftwareCatalog -Catalog $catalog
    return [pscustomobject]@{ Entries = @($entries); Path = $Path; Warnings = @() }
}

function Assert-SoftwareCatalog {
    <#
        Vérifie le format du catalogue et chaque entrée (Get-SoftwareEntryError). Lève une erreur
        unique qui liste tous les problèmes ; renvoie les entrées normalisées.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Catalog)

    $errors = New-Object System.Collections.Generic.List[string]
    $entries = New-Object System.Collections.Generic.List[object]
    if (-not ($Catalog -is [System.Management.Automation.PSCustomObject])) {
        throw 'software.json : objet { "CatalogVersion": 1, "Software": [ … ] } attendu.'
    }
    if (-not $Catalog.PSObject.Properties['CatalogVersion'] -or $Catalog.CatalogVersion -ne $script:SupportedCatalogVersion) {
        throw "software.json : CatalogVersion $script:SupportedCatalogVersion attendue."
    }
    if (-not $Catalog.PSObject.Properties['Software'] -or -not ($Catalog.Software -is [array] -or $null -eq $Catalog.Software)) {
        throw 'software.json : liste « Software » attendue.'
    }

    $ids = New-Object System.Collections.Generic.List[string]
    $index = 0
    foreach ($item in @($Catalog.Software)) {
        $entry = ConvertTo-SoftwareEntry -InputObject $item
        $label = if ($entry.Label) { " ($($entry.Label))" } else { '' }
        foreach ($problem in @(Get-SoftwareEntryError -Entry $entry -ExistingId $ids.ToArray())) {
            $errors.Add(('Software[{0}]{1} — {2}' -f $index, $label, $problem))
        }
        if ($entry.Id) { $ids.Add($entry.Id) }
        $entries.Add($entry)
        $index++
    }
    if ($errors.Count -gt 0) { throw ("software.json invalide :`n- " + ($errors -join "`n- ")) }
    return $entries.ToArray()
}

function Save-SoftwareCatalog {
    <#
        Écrit le catalogue : fichier temporaire dans le même dossier, puis remplacement atomique
        qui garde l'ancienne version en <fichier>.bak. JSON indenté sur deux espaces, UTF-8 sans BOM.
        Clé protégée en écriture : erreur explicite, le catalogue existant reste intact.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyCollection()][Parameter(Mandatory)][object[]]$Entries
    )
    # Validation avant écriture : un catalogue refusé à la relecture ne doit jamais être écrit.
    $document = [pscustomobject][ordered]@{ CatalogVersion = $script:SupportedCatalogVersion; Software = @($Entries) }
    $normalized = Assert-SoftwareCatalog -Catalog ($document | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
    $document.Software = @($normalized)
    $json = Format-JsonText -Json ($document | ConvertTo-Json -Depth 6 -Compress)

    $temporary = "$Path.tmp"
    $backup = "$Path.bak"
    try {
        [System.IO.File]::WriteAllText($temporary, $json + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try {
                [System.IO.File]::Replace($temporary, $Path, $backup)
            } catch [System.IO.IOException], [System.PlatformNotSupportedException] {
                # Systèmes de fichiers sans remplacement atomique (certaines clés FAT32) : copie de secours puis remplacement.
                Copy-Item -LiteralPath $Path -Destination $backup -Force -ErrorAction Stop
                Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
            }
        } else {
            Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
        }
    } catch {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $_.Exception.InnerException -is [System.UnauthorizedAccessException]) {
            throw "Catalogue non enregistré : la clé (ou le dossier $(Split-Path -Parent $Path)) est protégée en écriture."
        }
        throw "Catalogue non enregistré ($Path) : $($_.Exception.Message)"
    }
    return [pscustomobject]@{ Path = $Path; Backup = $(if (Test-Path -LiteralPath $backup) { $backup } else { $null }); Entries = @($normalized) }
}

function Format-JsonText {
    <#
        Indente un JSON compact sur deux espaces (la sortie de ConvertTo-Json en 5.1 est
        irrégulière). Parcourt le texte en tenant compte des chaînes et de leurs échappements.
    #>
    param([Parameter(Mandatory)][string]$Json)
    $builder = New-Object System.Text.StringBuilder
    $depth = 0
    $inString = $false
    $escaped = $false
    foreach ($char in $Json.ToCharArray()) {
        if ($inString) {
            [void]$builder.Append($char)
            if ($escaped) { $escaped = $false }
            elseif ($char -eq '\') { $escaped = $true }
            elseif ($char -eq '"') { $inString = $false }
            continue
        }
        switch ($char) {
            '"' { $inString = $true; [void]$builder.Append($char) }
            { $_ -eq '{' -or $_ -eq '[' } { $depth++; [void]$builder.Append($char).Append("`r`n").Append('  ' * $depth) }
            { $_ -eq '}' -or $_ -eq ']' } { $depth--; [void]$builder.Append("`r`n").Append('  ' * $depth).Append($char) }
            ',' { [void]$builder.Append($char).Append("`r`n").Append('  ' * $depth) }
            ':' { [void]$builder.Append(': ') }
            default { if (-not [char]::IsWhiteSpace($char)) { [void]$builder.Append($char) } }
        }
    }
    # Listes et objets vides sur une ligne : « [] » plutôt que « [\n  \n] ».
    return [regex]::Replace($builder.ToString(), '([\[{])\r\n\s*([\]}])', '$1$2')
}
