<#
    Section 6 — Installation Office via ODT.
    Cards générées depuis config.Office.Editions ; pastilles Avec / Sans Teams affichées pour les
    éditions qui ont une variante sans Teams ; cases générées depuis config.Office.OptionalApps.
    Le XML est produit par FastPrepare.Core (New-OdtInstallXml), jamais ici.
#>

Register-UiSection -Id 'office' -Number 6 -Column Right -XamlFile 'Sections\Office.xaml' -Initialize {
    param($Section, $Context)
    $office = $Context.Config.Office
    $editions = @($office.Editions)
    $cards = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $editions.Count; $i++) {
        $card = New-SelectableCard -Key $editions[$i].Key -Title $editions[$i].Label -IsLast:($i -eq $editions.Count - 1)
        $card.Add_Click({
                param($source, $routedEventArgs)
                Invoke-UiAction -Name 'édition Office' -Action {
                    Set-ExclusiveSelection -Card (Get-UiSection -Id 'office').State.Cards -Source $source
                    Update-OfficeView
                    Update-UiState
                }
            })
        [void]$Section.Controls.PnlOfficeEditions.Children.Add($card)
        $cards.Add($card)
    }
    $Section.State.Cards = $cards.ToArray()

    $includeChecks = New-Object System.Collections.Generic.List[object]
    foreach ($app in @($office.OptionalApps)) {
        $check = New-CheckItem -Content $app.Label -Tag $app.Id -IsChecked $true -Margin (New-Object System.Windows.Thickness(0, 3, 20, 3))
        $check.Add_Click({ Invoke-UiAction -Name 'applications Office' -Action { Update-OfficeView; Update-UiState } })
        [void]$Section.Controls.PnlIncludeItems.Children.Add($check)
        $includeChecks.Add($check)
    }
    $Section.State.IncludeChecks = $includeChecks.ToArray()

    # Licence : exactement une des deux pastilles
    $Section.Controls.PillTeams.Add_Click({
            Invoke-UiAction -Name 'licence Office' -Action {
                $c = (Get-UiSection -Id 'office').Controls
                $c.PillTeams.IsChecked = $true; $c.PillNoTeams.IsChecked = $false
                Update-OfficeView; Update-UiState
            }
        })
    $Section.Controls.PillNoTeams.Add_Click({
            Invoke-UiAction -Name 'licence Office' -Action {
                $c = (Get-UiSection -Id 'office').Controls
                $c.PillNoTeams.IsChecked = $true; $c.PillTeams.IsChecked = $false
                Update-OfficeView; Update-UiState
            }
        })
    Update-OfficeView
} -GetSelection {
    param($Section, $Selection)
    $key = Get-CheckedCardKey -Card $Section.State.Cards
    $Selection.Office.EditionKey = $key
    $Selection.Office.IncludedApps = @($Section.State.IncludeChecks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
    $withoutTeams = $false
    if ($key) {
        $edition = Get-OfficeEdition -OfficeConfig $script:Context.Config.Office -Key $key
        $withoutTeams = (Test-OfficeEditionHasNoTeamsVariant -Edition $edition) -and [bool]$Section.Controls.PillNoTeams.IsChecked
    }
    $Selection.Office.WithoutTeams = $withoutTeams
}

function Update-OfficeView {
    $section = Get-UiSection -Id 'office'
    $c = $section.Controls
    $office = $script:Context.Config.Office
    $key = Get-CheckedCardKey -Card $section.State.Cards

    $c.PnlInclude.IsEnabled = [bool]$key
    if (-not $key) {
        $c.PnlLicence.Visibility = 'Collapsed'
        $c.TxtOfficeInfo.Text = 'Aucune édition sélectionnée : Office ne sera pas installé.'
        return
    }

    $edition = Get-OfficeEdition -OfficeConfig $office -Key $key
    $hasNoTeams = Test-OfficeEditionHasNoTeamsVariant -Edition $edition
    $c.PnlLicence.Visibility = if ($hasNoTeams) { 'Visible' } else { 'Collapsed' }

    $productId = Get-OfficeProductId -Edition $edition -WithoutTeams:($hasNoTeams -and [bool]$c.PillNoTeams.IsChecked)
    $included = @($section.State.IncludeChecks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
    $excluded = @(Get-ExcludedOfficeApp -OptionalApp @($office.OptionalApps) -IncludedId $included)
    $excludeText = if ($excluded.Count) { 'exclus : ' + ($excluded -join ', ') } else { 'aucune exclusion' }
    $c.TxtOfficeInfo.Text = 'XML généré à la volée dans {0} · ID produit {1} · {2} · activation manuelle plus tard' -f $office.OdtFolder, $productId, $excludeText
}
