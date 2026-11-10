<#
    Onglet Réglages — Catalogue des logiciels de la section 8 (itération 9, DEC17 à DEC19).
    Affichage seulement : règles dans FastPrepare.Core (SoftwareCatalog.ps1), enregistrement et
    test dans FastPrepare.Application (SoftwareCatalog.ps1). Le test tourne en arrière-plan et
    ne télécharge ni n'installe rien.
#>

Register-UiSection -Id 'software-catalog-settings' -Number 100 -Column Settings -XamlFile 'Sections\SoftwareCatalogSettings.xaml' -Initialize {
    param($Section, $Context)
    $c = $Section.Controls
    $state = $Section.State
    $state.EditingId = $null      # identifiant de l'entrée modifiée ; $null = nouveau logiciel
    $state.Revision = 0           # incrémenté à chaque modification du formulaire
    $state.TestedRevision = -1    # révision du formulaire testée avec succès
    $state.TestRunning = $false
    $state.Loading = $false       # remplissage du formulaire par le code : pas d'événement « modifié »

    $c.TxtSwIntro.Text = ("Logiciels proposés dans la section 8. Enregistrés dans {0} sur la clé (ancienne version gardée en .bak) : " +
        "cette page ne modifie jamais le poste, même en mode réel. Testez chaque entrée avant de l'enregistrer.") -f $Context.Paths.SoftwareCatalog

    $onEdit = { Invoke-UiAction -Name 'catalogue des logiciels' -Action { Update-SoftwareFormState -Changed } }
    foreach ($name in 'TxtSwLabel', 'TxtSwWingetId', 'TxtSwOverride', 'TxtSwUrl', 'TxtSwFileName', 'TxtSwArguments', 'TxtSwSigner', 'TxtSwSha256') {
        $c[$name].Add_TextChanged($onEdit)
    }
    $c.ChkSwDefault.Add_Click($onEdit)
    $c.CmbSwSource.Add_SelectionChanged($onEdit)
    $c.CmbSwScope.Add_SelectionChanged($onEdit)
    $c.RbSwWinget.Add_Checked($onEdit)
    $c.RbSwDownload.Add_Checked($onEdit)

    $c.LstSw.Add_SelectionChanged({ Invoke-UiAction -Name 'catalogue des logiciels' -Action { Open-SoftwareCatalogSelection } })
    $c.BtnSwNew.Add_Click({ Invoke-UiAction -Name 'catalogue des logiciels' -Action { (Get-UiSection -Id 'software-catalog-settings').Controls.LstSw.SelectedItem = $null; Open-SoftwareForm -Entry $null } })
    $c.BtnSwCancel.Add_Click({ Invoke-UiAction -Name 'catalogue des logiciels' -Action { Open-SoftwareCatalogSelection } })
    $c.BtnSwTest.Add_Click({ Invoke-UiAction -Name 'test du logiciel' -Action { Start-SoftwareFormTest } })
    $c.BtnSwSave.Add_Click({ Invoke-UiAction -Name 'enregistrement du logiciel' -Action { Save-SoftwareForm } })
    $c.BtnSwRemove.Add_Click({ Invoke-UiAction -Name 'retrait du logiciel' -Action { Remove-SoftwareFormEntry } })

    Update-SoftwareCatalogList -Context $Context
    Open-SoftwareForm -Entry $null
}

function Get-SoftwareCatalogSection { return (Get-UiSection -Id 'software-catalog-settings') }

function Update-SoftwareCatalogList {
    <# Remplit la liste depuis Context.SoftwareCatalog ; -SelectId : entrée à sélectionner ensuite. #>
    param($Context, [string]$SelectId)
    $section = Get-SoftwareCatalogSection
    $list = $section.Controls.LstSw
    $section.State.Loading = $true
    try {
        $list.Items.Clear()
        foreach ($entry in @($Context.SoftwareCatalog)) {
            $item = [System.Windows.Controls.ListBoxItem]::new()
            $detail = if ($entry.Install.Type -eq 'winget') { 'winget · {0}' -f $entry.Install.Id } else { 'lien direct · {0}' -f $entry.Install.FileName }
            $text = [System.Windows.Controls.TextBlock]::new()
            $text.Text = '{0}  —  {1}' -f $entry.Label, $detail
            $text.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $item.Content = $text
            $item.ToolTip = Format-SoftwareInstallCommand -Entry $entry
            $item.Tag = $entry
            [void]$list.Items.Add($item)
            if ($SelectId -and $entry.Id -eq $SelectId) { $list.SelectedItem = $item }
        }
    } finally {
        $section.State.Loading = $false
    }
}

function Open-SoftwareCatalogSelection {
    <# Affiche dans le formulaire l'entrée sélectionnée dans la liste (ou un formulaire vide). #>
    $section = Get-SoftwareCatalogSection
    if ($section.State.Loading) { return }
    $item = $section.Controls.LstSw.SelectedItem
    Open-SoftwareForm -Entry $(if ($item) { $item.Tag } else { $null })
}

function Open-SoftwareForm {
    <# Remplit le formulaire avec une entrée du catalogue, ou le vide pour un nouveau logiciel. #>
    param($Entry)
    $section = Get-SoftwareCatalogSection
    $c = $section.Controls
    $section.State.Loading = $true
    try {
        $install = if ($Entry) { $Entry.Install } else { $null }
        $isDownload = $install -and $install.Type -eq 'download'
        $c.TxtSwLabel.Text = if ($Entry) { $Entry.Label } else { '' }
        $c.ChkSwDefault.IsChecked = if ($Entry) { [bool]$Entry.DefaultChecked } else { $false }
        $c.RbSwWinget.IsChecked = -not $isDownload
        $c.RbSwDownload.IsChecked = [bool]$isDownload
        $winget = $install -and $install.Type -eq 'winget'
        $c.TxtSwWingetId.Text = if ($winget) { $install.Id } else { '' }
        $c.CmbSwSource.SelectedIndex = if ($winget -and $install.Source -eq 'msstore') { 1 } else { 0 }
        $c.TxtSwOverride.Text = if ($winget) { $install.Override } else { '' }
        # Portée : celle de l'entrée ; « pour tous les utilisateurs » pour un nouveau logiciel (DEC22).
        $scope = if ($winget) { [string]$install.Scope } else { 'machine' }
        foreach ($scopeItem in $c.CmbSwScope.Items) { if ([string]$scopeItem.Tag -eq $scope) { $c.CmbSwScope.SelectedItem = $scopeItem } }
        foreach ($pair in @(@('TxtSwUrl', 'Url'), @('TxtSwFileName', 'FileName'), @('TxtSwArguments', 'Arguments'), @('TxtSwSigner', 'ExpectedSigner'), @('TxtSwSha256', 'Sha256'))) {
            $c[$pair[0]].Text = if ($isDownload) { [string]$install.($pair[1]) } else { '' }
        }
        $section.State.EditingId = if ($Entry) { $Entry.Id } else { $null }
        $c.TxtSwFormTitle.Text = if ($Entry) { 'Modifier « {0} »' -f $Entry.Label } else { 'Nouveau logiciel' }
        $c.BtnSwRemove.IsEnabled = [bool]$Entry
        $c.PnlSwTest.Children.Clear()
    } finally {
        $section.State.Loading = $false
    }
    $section.State.Revision++
    Update-SoftwareFormState
}

function Get-SoftwareFormEntry {
    <# Entrée normalisée décrite par le formulaire (identifiant déduit du libellé pour un nouveau logiciel). #>
    $section = Get-SoftwareCatalogSection
    $c = $section.Controls
    $others = @(@($script:Context.SoftwareCatalog) | Where-Object { $_.Id -ne $section.State.EditingId } | ForEach-Object { $_.Id })
    $id = if ($section.State.EditingId) { $section.State.EditingId } else { New-SoftwareId -Label $c.TxtSwLabel.Text -ExistingId $others }
    $install = if ($c.RbSwDownload.IsChecked) {
        [pscustomobject]@{ Type = 'download'; Url = $c.TxtSwUrl.Text; FileName = $c.TxtSwFileName.Text; Arguments = $c.TxtSwArguments.Text; Sha256 = $c.TxtSwSha256.Text; ExpectedSigner = $c.TxtSwSigner.Text }
    } else {
        [pscustomobject]@{ Type = 'winget'; Id = $c.TxtSwWingetId.Text; Source = [string]$c.CmbSwSource.SelectedItem.Content; Override = $c.TxtSwOverride.Text; Scope = [string]$c.CmbSwScope.SelectedItem.Tag }
    }
    $entry = ConvertTo-SoftwareEntry -InputObject ([pscustomobject]@{ Id = $id; Label = $c.TxtSwLabel.Text; DefaultChecked = [bool]$c.ChkSwDefault.IsChecked; Install = $install })
    return [pscustomobject]@{ Entry = $entry; Problems = @(Get-SoftwareEntryError -Entry $entry -ExistingId $others) }
}

function Update-SoftwareFormState {
    <#
        Après chaque modification : champs du type choisi, aperçu de la commande, problèmes de
        saisie, boutons. -Changed : le formulaire diffère de ce qui a été testé.
    #>
    param([switch]$Changed)
    $section = Get-SoftwareCatalogSection
    if ($section.State.Loading) { return }
    $c = $section.Controls
    if ($Changed) {
        $section.State.Revision++
        if ($c.PnlSwTest.Children.Count -gt 0 -and $section.State.TestedRevision -ne $section.State.Revision) {
            $c.PnlSwTest.Children.Clear()
            [void]$c.PnlSwTest.Children.Add((New-SoftwareTestLine -Level 'ATTN' -Text 'Formulaire modifié depuis le dernier test : testez de nouveau.'))
        }
    }
    $isDownload = [bool]$c.RbSwDownload.IsChecked
    $c.GrdSwWinget.Visibility = if ($isDownload) { 'Collapsed' } else { 'Visible' }
    $c.GrdSwDownload.Visibility = if ($isDownload) { 'Visible' } else { 'Collapsed' }

    $form = Get-SoftwareFormEntry
    $c.TxtSwId.Text = if ($form.Entry.Label) { $form.Entry.Id } else { '(déduit du libellé)' }
    $c.TxtSwCommand.Text = Format-SoftwareInstallCommand -Entry $form.Entry
    $c.TxtSwProblems.Text = ($form.Problems | ForEach-Object { '• ' + $_ }) -join "`n"
    $c.BtnSwSave.IsEnabled = ($form.Problems.Count -eq 0) -and -not $section.State.TestRunning
    $c.BtnSwTest.IsEnabled = -not $section.State.TestRunning
}

function New-SoftwareTestLine {
    <# Ligne de résultat du test, colorée selon son niveau. #>
    param([string]$Level, [string]$Text)
    $block = [System.Windows.Controls.TextBlock]::new()
    $block.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $block.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
    $symbol, $brush = switch ($Level) {
        'OK' { '✓', 'SuccessBrush' }
        'ERREUR' { '✗', 'ErrorBrush' }
        'ATTN' { '⚠', 'WarningBrush' }
        default { '•', 'TextSecondaryBrush' }
    }
    $block.Text = '{0} {1}' -f $symbol, $Text
    $block.Foreground = Get-ThemeResource -Key $brush
    return $block
}

function Start-SoftwareFormTest {
    <# Lance le test de l'entrée du formulaire en arrière-plan ; le résultat s'affiche ligne à ligne. #>
    $section = Get-SoftwareCatalogSection
    $c = $section.Controls
    $form = Get-SoftwareFormEntry
    $section.State.TestRunning = $true
    $section.State.TestingRevision = $section.State.Revision
    $c.PnlSwTest.Children.Clear()
    [void]$c.PnlSwTest.Children.Add((New-SoftwareTestLine -Level 'INFO' -Text 'Test en cours (aucun téléchargement, aucune installation)…'))
    Update-SoftwareFormState

    $work = Start-SoftwareCatalogTest -Entry $form.Entry -Context $script:Context
    Register-UiBackgroundWork -Work $work -OnCompleted {
        param($result)
        $section = Get-SoftwareCatalogSection
        $section.State.TestRunning = $false
        $c = $section.Controls
        $c.PnlSwTest.Children.Clear()
        $outcome = @($result)[-1]
        foreach ($line in @($outcome.Lines)) { [void]$c.PnlSwTest.Children.Add((New-SoftwareTestLine -Level $line.Level -Text $line.Text)) }
        if ($outcome.Succeeded -and $section.State.TestingRevision -eq $section.State.Revision) { $section.State.TestedRevision = $section.State.Revision }
        Update-SoftwareFormState
    } -OnFailed {
        param($message)
        $section = Get-SoftwareCatalogSection
        $section.State.TestRunning = $false
        $section.Controls.PnlSwTest.Children.Clear()
        [void]$section.Controls.PnlSwTest.Children.Add((New-SoftwareTestLine -Level 'ERREUR' -Text "Test interrompu : $message"))
        Update-SoftwareFormState
    }
}

function Save-SoftwareForm {
    <# Enregistre l'entrée du formulaire ; confirmation si elle n'a pas été testée avec succès (DEC19). #>
    $section = Get-SoftwareCatalogSection
    $form = Get-SoftwareFormEntry
    if ($form.Problems.Count -gt 0) { return }
    if ($section.State.TestedRevision -ne $section.State.Revision) {
        $answer = [System.Windows.MessageBox]::Show(
            ("« {0} » n'a pas été testé avec succès depuis sa dernière modification.`n`nUne erreur de saisie ne serait découverte qu'à l'exécution réelle. Enregistrer quand même ?" -f $form.Entry.Label),
            'Catalogue des logiciels', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
    }
    try {
        $saved = Set-SoftwareCatalogEntry -Context $script:Context -Entry $form.Entry -PreviousId $section.State.EditingId
    } catch {
        [void][System.Windows.MessageBox]::Show($_.Exception.Message, 'Catalogue des logiciels', 'OK', 'Error')
        return
    }
    $tested = $section.State.TestedRevision -eq $section.State.Revision
    Update-SoftwareCatalogList -Context $script:Context -SelectId $saved.Id
    Open-SoftwareForm -Entry $saved
    if ($tested) { $section.State.TestedRevision = $section.State.Revision }
    [void]$section.Controls.PnlSwTest.Children.Add((New-SoftwareTestLine -Level 'OK' -Text ('Enregistré : « {0} » apparaît dans la section 8 de l''onglet Préparation.' -f $saved.Label)))
    Publish-SettingsChanged
}

function Remove-SoftwareFormEntry {
    <# Retire du catalogue l'entrée affichée, après confirmation. #>
    $section = Get-SoftwareCatalogSection
    $id = $section.State.EditingId
    if (-not $id) { return }
    $entry = @($script:Context.SoftwareCatalog) | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    $answer = [System.Windows.MessageBox]::Show(("Retirer « {0} » du catalogue ?`nIl ne sera plus proposé en section 8." -f $entry.Label), 'Catalogue des logiciels', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }
    try {
        Remove-SoftwareCatalogEntry -Context $script:Context -Id $id
    } catch {
        [void][System.Windows.MessageBox]::Show($_.Exception.Message, 'Catalogue des logiciels', 'OK', 'Error')
        return
    }
    Update-SoftwareCatalogList -Context $script:Context
    Open-SoftwareForm -Entry $null
    Publish-SettingsChanged
}
