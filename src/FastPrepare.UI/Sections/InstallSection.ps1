<#
    Section « Installations » : tout ce qui s'installe se coche ici et s'exécute dans une seule
    étape (DEC26).
    - Catalogue : une case par entrée de software.json (Context.SoftwareCatalog, modifiable dans
      l'onglet Réglages) applicable au constructeur détecté. L'outil d'un autre constructeur n'est
      jamais proposé (DEC25) : la règle est dans FastPrepare.Core (Select-ApplicableSoftware).
    - Office : cards générées depuis config.Office.Editions ; pastilles Avec / Sans Teams pour les
      éditions qui ont une variante sans Teams ; cases depuis config.Office.OptionalApps. Le XML
      est produit par FastPrepare.Core (New-OdtInstallXml), jamais ici.
#>

Register-UiSection -Id 'install' -Number 5 -Column Right -XamlFile 'Sections\Install.xaml' -Initialize {
    param($Section, $Context)
    $Section.State.Checks = @()
    # Constructeur inconnu tant que le relevé du poste n'est pas arrivé : seules les entrées
    # proposées sur tous les postes sont affichées.
    $Section.State.Manufacturer = ''
    $Section.State.SnapshotReady = $false
    Update-InstallCatalogList -Section $Section -Context $Context -KeepState:$false
    Initialize-InstallOfficeBlock -Section $Section -Context $Context
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $Section.State.Manufacturer = [string]$Snapshot.Identity.Manufacturer
    $Section.State.SnapshotReady = $true
    Update-InstallCatalogList -Section $Section -Context $Context -KeepState:$true
} -OnSettingsChanged {
    param($Section, $Context)
    Update-InstallCatalogList -Section $Section -Context $Context -KeepState:$true
} -GetSelection {
    param($Section, $Selection)
    $Selection.Catalog.Ids = @($Section.State.Checks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })

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

function Update-InstallCatalogList {
    <#
        Une case par entrée du catalogue applicable au poste, celles propres au constructeur en
        tête ; info-bulle = commande d'installation. -KeepState : une case existante garde son
        état ; une entrée nouvelle prend sa valeur « coché par défaut ».
    #>
    param($Section, $Context, [switch]$KeepState)
    $previous = @{}
    if ($KeepState) { foreach ($check in @($Section.State.Checks)) { $previous[[string]$check.Tag] = [bool]$check.IsChecked } }

    $manufacturer = [string]$Section.State.Manufacturer
    $applicable = @(Select-ApplicableSoftware -Catalog @($Context.SoftwareCatalog) -Manufacturer $manufacturer)
    $vendor = @($applicable | Where-Object { $_.ManufacturerPattern })
    $common = @($applicable | Where-Object { -not $_.ManufacturerPattern })

    $panel = $Section.Controls.PnlSoftware
    $panel.Children.Clear()
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($software in ($vendor + $common)) {
        $checked = if ($previous.ContainsKey($software.Id)) { $previous[$software.Id] } else { [bool]$software.DefaultChecked }
        $check = New-CheckItem -Content $software.Label -Tag $software.Id -IsChecked $checked
        $check.ToolTip = Format-SoftwareInstallCommand -Entry $software
        # Cocher ou décocher une entrée change la section Mises à jour (pilotes et BIOS).
        $check.Add_Click({ Invoke-UiAction -Name 'installations' -Action { Update-UiState } })
        [void]$panel.Children.Add($check)
        $checks.Add($check)
    }
    $Section.State.Checks = $checks.ToArray()
    $Section.Controls.TxtSoftwareNone.Visibility = if ($checks.Count -eq 0) { 'Visible' } else { 'Collapsed' }

    $Section.Controls.TxtVendorInfo.Text = if (-not $Section.State.SnapshotReady) {
        'Détection du constructeur en cours…'
    } elseif (-not $manufacturer) {
        'Constructeur non détecté : aucun outil constructeur proposé.'
    } elseif ($vendor.Count -gt 0) {
        'Constructeur détecté : {0} — outil proposé : {1}' -f $manufacturer, (@($vendor | ForEach-Object { $_.Label }) -join ', ')
    } else {
        'Constructeur détecté : {0} — aucun outil constructeur au catalogue pour cette marque.' -f $manufacturer
    }
}

function Initialize-InstallOfficeBlock {
    <# Cards d'édition, pastilles de licence et cases des applications incluses. #>
    param($Section, $Context)
    $office = $Context.Config.Office
    $editions = @($office.Editions)
    $cards = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $editions.Count; $i++) {
        $card = New-SelectableCard -Key $editions[$i].Key -Title $editions[$i].Label -IsLast:($i -eq $editions.Count - 1)
        $card.Add_Click({
                param($source, $routedEventArgs)
                Invoke-UiAction -Name 'édition Office' -Action {
                    Set-ExclusiveSelection -Card (Get-UiSection -Id 'install').State.Cards -Source $source
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
                $c = (Get-UiSection -Id 'install').Controls
                $c.PillTeams.IsChecked = $true; $c.PillNoTeams.IsChecked = $false
                Update-OfficeView; Update-UiState
            }
        })
    $Section.Controls.PillNoTeams.Add_Click({
            Invoke-UiAction -Name 'licence Office' -Action {
                $c = (Get-UiSection -Id 'install').Controls
                $c.PillNoTeams.IsChecked = $true; $c.PillTeams.IsChecked = $false
                Update-OfficeView; Update-UiState
            }
        })
    Update-OfficeView
}

function Update-OfficeView {
    $section = Get-UiSection -Id 'install'
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
    $c.TxtOfficeInfo.Text = 'XML généré à la volée dans {0} · ID produit {1} · {2} · activation manuelle plus tard' -f $script:Context.Paths.Odt, $productId, $excludeText
}
