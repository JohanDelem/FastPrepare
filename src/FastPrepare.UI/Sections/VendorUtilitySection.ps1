<#
    Section 5 — Installation d'utilitaire constructeur.
    Cards générées depuis config.Utilities ; une seule sélectionnable ; présélection selon le
    constructeur détecté. Ajouter une marque = un bloc dans config.json (+ un logo facultatif).
    En mode réel, le choix d'une card (clic ou présélection) lance le téléchargement anticipé
    (FastPrepare.Application, Start-Prefetch) ; en simulation, rien n'est téléchargé.
#>

Register-UiSection -Id 'vendor-utility' -Number 5 -Column Right -XamlFile 'Sections\VendorUtility.xaml' -Initialize {
    param($Section, $Context)
    $utilities = $Context.Config.Utilities
    $keys = @($utilities.PSObject.Properties | ForEach-Object { $_.Name })
    $cards = New-Object System.Collections.Generic.List[object]
    $Section.State.UserChose = $false
    $Section.State.PrefetchStatus = @{}

    for ($i = 0; $i -lt $keys.Count; $i++) {
        $utility = $utilities.($keys[$i])
        $logoPath = if ($utility.Logo) { Join-Path $Context.Paths.Logos $utility.Logo } else { $null }
        $card = New-SelectableCard -Key $keys[$i] -Title $utility.Label -Subtitle $utility.Subtitle -LogoPath $logoPath -IsLast:($i -eq $keys.Count - 1) -Log $Context.Log
        $card.Add_Click({
                param($source, $routedEventArgs)
                Invoke-UiAction -Name 'utilitaire constructeur' -Action {
                    $section = Get-UiSection -Id 'vendor-utility'
                    $section.State.UserChose = $true
                    Set-ExclusiveSelection -Card $section.State.Cards -Source $source
                    Update-VendorUtilityStatus
                    $key = Get-CheckedCardKey -Card $section.State.Cards
                    if ($key) { Start-VendorPrefetch -Key $key }
                    Update-UiState
                }
            })
        [void]$Section.Controls.PnlUtilities.Children.Add($card)
        $cards.Add($card)
    }
    $Section.State.Cards = $cards.ToArray()
    Update-VendorUtilityStatus
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    # Présélection selon le constructeur, sauf si le technicien a déjà cliqué une card pendant la détection.
    if ($Snapshot.SuggestedUtilityKey -and -not $Section.State.UserChose) {
        foreach ($card in $Section.State.Cards) { $card.IsChecked = ([string]$card.Tag -eq $Snapshot.SuggestedUtilityKey) }
        Start-VendorPrefetch -Key $Snapshot.SuggestedUtilityKey
    }
    Update-VendorUtilityStatus
} -GetSelection {
    param($Section, $Selection)
    $Selection.VendorUtility.Key = Get-CheckedCardKey -Card $Section.State.Cards
}

function Update-VendorUtilityStatus {
    $section = Get-UiSection -Id 'vendor-utility'
    $key = Get-CheckedCardKey -Card $section.State.Cards
    if (-not $key) {
        $section.Controls.TxtUtilStatus.Text = 'Aucun utilitaire sélectionné. Cliquer à nouveau sur une card la désélectionne.'
        return
    }
    $utility = $script:Context.Config.Utilities.$key
    $sources = foreach ($item in @($utility.Install)) {
        if ($item.Type -eq 'winget') { 'winget {0} (source {1})' -f $item.Id, $item.Source }
        else { 'lien direct {0}' -f $item.FileName }
    }
    $status = $section.State.PrefetchStatus[$key]
    $suffix = if ($status) { ' · ' + $status } else { '' }
    $section.Controls.TxtUtilStatus.Text = '{0} · {1}{2}' -f $utility.Tool, ($sources -join ' + '), $suffix
}

function Start-VendorPrefetch {
    <# Téléchargement anticipé de l'utilitaire choisi (mode réel seulement), une fois par marque. #>
    param([string]$Key)
    $section = Get-UiSection -Id 'vendor-utility'
    $context = $script:Context
    $tool = $context.Config.Utilities.$Key.Tool
    if ($context.Mode -eq 'Simulation') {
        Write-RunLog -Log $context.Log -Level SIMU -Message ('Utilitaire sélectionné : {0} (téléchargement anticipé simulé)' -f $tool)
        return
    }
    if ($section.State.PrefetchStatus.ContainsKey($Key)) { return }
    if (-not (Test-PrefetchUseful -UtilityKey $Key -Context $context)) {
        $section.State.PrefetchStatus[$Key] = 'installation par winget à l''exécution'
        Update-VendorUtilityStatus
        return
    }
    $section.State.PrefetchStatus[$Key] = 'préchargement en cours…'
    Update-VendorUtilityStatus
    Write-RunLog -Log $context.Log -Message ('Préchargement de {0} lancé' -f $tool)
    $work = Start-Prefetch -UtilityKey $Key -Context $context
    $section.State.PendingPrefetchKey = $Key
    Register-UiBackgroundWork -Work $work -OnCompleted {
        param($result)
        $prefetch = @($result) | Select-Object -Last 1
        $state = (Get-UiSection -Id 'vendor-utility').State
        $state.PrefetchStatus[$prefetch.UtilityKey] = if (@($prefetch.Errors).Count -gt 0) { 'préchargement incomplet (voir le journal)' } else { 'préchargé' }
        Update-VendorUtilityStatus
    } -OnFailed {
        param($message)
        Write-RunLog -Log $script:Context.Log -Level ATTN -Message "Préchargement impossible : $message"
        $state = (Get-UiSection -Id 'vendor-utility').State
        $state.PrefetchStatus[$state.PendingPrefetchKey] = 'préchargement impossible (voir le journal)'
        Update-VendorUtilityStatus
    }
}
