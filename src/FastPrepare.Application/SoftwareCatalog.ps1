<#
    Modification et test du catalogue des logiciels de la section 8 (itération 9, DEC17 à DEC19).
    Aucun type WPF : l'onglet Réglages n'en est que l'affichage. Les règles d'une entrée sont dans
    FastPrepare.Core (SoftwareCatalog.ps1), l'écriture du fichier dans FastPrepare.Infrastructure.
#>

function Set-SoftwareCatalogEntry {
    <#
        Ajoute une entrée, ou remplace celle dont l'identifiant est -PreviousId. Refus (erreur qui
        liste les problèmes) si l'entrée n'est pas valable : rien n'est écrit. Renvoie l'entrée enregistrée.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Entry,
        [string]$PreviousId
    )
    $normalized = ConvertTo-SoftwareEntry -InputObject $Entry
    $others = @(@($Context.SoftwareCatalog) | Where-Object { $_.Id -ne $PreviousId })
    $problems = @(Get-SoftwareEntryError -Entry $normalized -ExistingId @($others | ForEach-Object { $_.Id }))
    if ($problems.Count -gt 0) { throw ("Logiciel non enregistré :`n- " + ($problems -join "`n- ")) }

    # Remplacement à la même place ; ajout en fin de liste.
    $entries = New-Object System.Collections.Generic.List[object]
    $replaced = $false
    foreach ($existing in @($Context.SoftwareCatalog)) {
        if ($PreviousId -and $existing.Id -eq $PreviousId) { $entries.Add($normalized); $replaced = $true }
        else { $entries.Add($existing) }
    }
    if (-not $replaced) { $entries.Add($normalized) }

    $saved = Save-SoftwareCatalog -Path $Context.Paths.SoftwareCatalog -Entries $entries.ToArray()
    $Context.SoftwareCatalog = @($saved.Entries)
    $verb = if ($replaced) { 'modifié' } else { 'ajouté' }
    Write-RunLog -Log $Context.Log -Level OK -Message ('Catalogue des logiciels : {0} {1} ({2})' -f $normalized.Label, $verb, (Format-SoftwareInstallCommand -Entry $normalized))
    return $normalized
}

function Remove-SoftwareCatalogEntry {
    <# Retire une entrée du catalogue (écriture atomique). Identifiant inconnu : erreur. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Id
    )
    $entry = @($Context.SoftwareCatalog) | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $entry) { throw "Logiciel inconnu dans le catalogue : '$Id'." }
    $remaining = @(@($Context.SoftwareCatalog) | Where-Object { $_.Id -ne $Id })
    $saved = Save-SoftwareCatalog -Path $Context.Paths.SoftwareCatalog -Entries $remaining
    $Context.SoftwareCatalog = @($saved.Entries)
    Write-RunLog -Log $Context.Log -Level OK -Message ('Catalogue des logiciels : {0} retiré' -f $entry.Label)
}

function Test-SoftwareCatalogEntry {
    <#
        Teste une entrée SANS rien télécharger ni installer (DEC18) : règles de saisie, puis
        winget show (paquet trouvé) ou en-têtes HTTP du lien (fichier, pas une page web).
        Renvoie { Succeeded, Lines = @({ Level ('OK'|'ERREUR'|'ATTN'|'INFO'), Text }) }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)]$Context
    )
    $lines = New-Object System.Collections.Generic.List[object]
    $add = { param($Level, $Text) $lines.Add([pscustomobject]@{ Level = $Level; Text = $Text }) }
    $entry = ConvertTo-SoftwareEntry -InputObject $Entry

    # L'unicité de l'identifiant ne concerne que l'enregistrement : elle n'est pas testée ici.
    $problems = @(Get-SoftwareEntryError -Entry $entry)
    foreach ($problem in $problems) { & $add 'ERREUR' $problem }

    if ($problems.Count -eq 0) {
        $install = $entry.Install
        try {
            if ($install.Type -eq 'winget') {
                if (-not (Test-Winget)) { throw "winget indisponible sur ce poste : test impossible (l'installation réelle tentera de le réenregistrer)" }
                $info = Get-WingetPackageInfo -Id $install.Id -Source $install.Source -SourceRepair (Get-WingetSourceRepair -Context $Context) -Log $Context.Log
                $name = if ($info.Name) { $info.Name } else { $install.Id }
                & $add 'OK' ('Paquet trouvé : {0}, version {1} (source {2})' -f $name, $info.Version, $install.Source)
                if ($install.Override) { & $add 'ATTN' "Options d'installation (--override) : vérifiées seulement à l'installation réelle" }
            } else {
                $head = Test-RemoteFile -Url $install.Url
                if ($head.StatusCode -ne 200) { throw ('le lien répond {0} au lieu de 200' -f $head.StatusCode) }
                if ($head.FinalUrl -notmatch '^https://') { throw ('redirigé hors https : {0}' -f $head.FinalUrl) }
                if ($head.ContentType -match '^text/html') { throw "le lien mène à une page web, pas à un fichier : utilisez le lien direct vers l'installateur" }
                $size = if ($head.ContentLength) { '{0:N1} Mo' -f ($head.ContentLength / 1MB) } else { 'taille non annoncée' }
                $type = if ($head.ContentType) { $head.ContentType } else { 'type non annoncé' }
                & $add 'OK' ('Lien valide : fichier de {0} ({1})' -f $size, $type)
                # Serveur seulement : l'adresse finale est souvent un lien signé très long.
                if ($head.FinalUrl -ne $install.Url) { & $add 'INFO' ('Redirigé vers le serveur {0}' -f ([System.Uri]$head.FinalUrl).Host) }
                & $add 'ATTN' ("Signature « {0} »{1} et arguments silencieux : vérifiés seulement à l'installation réelle" -f $install.ExpectedSigner, $(if ($install.Sha256) { ', empreinte' } else { '' }))
            }
        } catch {
            & $add 'ERREUR' $_.Exception.Message
        }
    }

    $succeeded = -not ($lines | Where-Object { $_.Level -eq 'ERREUR' })
    $label = if ($entry.Label) { $entry.Label } else { '(sans libellé)' }
    Write-RunLog -Log $Context.Log -Level $(if ($succeeded) { 'OK' } else { 'ERREUR' }) -Message ('Test du logiciel {0} (sans téléchargement ni installation) : {1}' -f $label, $(if ($succeeded) { 'réussi' } else { 'échec' }))
    foreach ($line in $lines) { Write-RunLog -Log $Context.Log -Level DEBUG -Message ('     ' + $line.Text) }
    return [pscustomobject]@{ Succeeded = [bool]$succeeded; Lines = $lines.ToArray() }
}

function Start-SoftwareCatalogTest {
    <# Lance Test-SoftwareCatalogEntry dans un runspace (winget show prend quelques secondes). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)]$Context
    )
    return Start-BackgroundWork -Name 'test-catalogue' -ModulePath $Context.ModulePaths -Argument @($Entry, $Context) -ScriptBlock {
        param($Entry, $Context)
        Test-SoftwareCatalogEntry -Entry $Entry -Context $Context
    }
}
