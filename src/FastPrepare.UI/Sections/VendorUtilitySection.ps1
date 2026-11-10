<#
    Section 5 — Installation d'utilitaire constructeur.
    Cards générées depuis config.Utilities ; une seule sélectionnable ; présélection selon le
    constructeur détecté. Ajouter une marque = un bloc dans config.json (+ un logo facultatif).
#>

Register-UiSection -Id 'vendor-utility' -Number 5 -Column Right -XamlFile 'Sections\VendorUtility.xaml' -Initialize {
    param($Section, $Context)
    $utilities = $Context.Config.Utilities
    $keys = @($utilities.PSObject.Properties | ForEach-Object { $_.Name })
    $cards = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $keys.Count; $i++) {
        $utility = $utilities.($keys[$i])
        $logoPath = if ($utility.Logo) { Join-Path $Context.Paths.Logos $utility.Logo } else { $null }
        $card = New-SelectableCard -Key $keys[$i] -Title $utility.Label -Subtitle $utility.Subtitle -LogoPath $logoPath -IsLast:($i -eq $keys.Count - 1) -Log $Context.Log
        $card.Add_Click({
                param($source, $routedEventArgs)
                Invoke-UiAction -Name 'utilitaire constructeur' -Action {
                    $section = Get-UiSection -Id 'vendor-utility'
                    Set-ExclusiveSelection -Card $section.State.Cards -Source $source
                    Update-VendorUtilityStatus
                    $key = Get-CheckedCardKey -Card $section.State.Cards
                    if ($key) {
                        Write-RunLog -Log $script:Context.Log -Level SIMU -Message ('Utilitaire sélectionné : {0} (téléchargement anticipé simulé)' -f $script:Context.Config.Utilities.$key.Tool)
                    }
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
    if ($Snapshot.SuggestedUtilityKey) {
        foreach ($card in $Section.State.Cards) { $card.IsChecked = ([string]$card.Tag -eq $Snapshot.SuggestedUtilityKey) }
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
    $section.Controls.TxtUtilStatus.Text = '{0} · {1}' -f $utility.Tool, ($sources -join ' + ')
}
