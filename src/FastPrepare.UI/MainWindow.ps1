<#
    Assemblage de la fenêtre : coquille, sections, pompe, bouton Lancer.
    Aucune règle métier ici : la validité vient des sections (Validate), les actions du moteur
    (FastPrepare.Application).
#>

$script:Context = $null
$script:Shell = $null
$script:Snapshot = $null

function Start-MainWindow {
    <# Construit et affiche la fenêtre ; rend la main à sa fermeture. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    $script:Context = $Context
    $xamlFolder = Join-Path $PSScriptRoot 'Xaml'

    Initialize-WpfApplication -ThemePath (Join-Path $xamlFolder 'Theme.xaml')
    $script:Shell = Import-Xaml -Path (Join-Path $xamlFolder 'MainWindow.xaml')
    $shell = $script:Shell.Controls
    $window = $script:Shell.Root

    Initialize-LogView -RichTextBox $shell.RtbLog
    $shell.BdSimu.Visibility = if ($Context.Mode -eq 'Simulation') { 'Visible' } else { 'Collapsed' }
    Set-MemoText -TextBlock $shell.TxtMemo -Reminder @($Context.Config.ManualReminders)

    foreach ($section in (Get-UiSection)) {
        if ($section.XamlFile) {
            $fragment = Import-Xaml -Path (Join-Path $xamlFolder $section.XamlFile)
            $section.Root = $fragment.Root
            $section.Controls = $fragment.Controls
            $column = if ($section.Column -eq 'Left') { $shell.ColLeft } else { $shell.ColRight }
            [void]$column.Children.Add($fragment.Root)
        } else {
            $section.Controls = $shell
        }
        Invoke-UiSectionCallback -Section $section -Name Initialize -Arguments @($Context) | Out-Null
    }

    $shell.BtnGo.Add_Click({ Invoke-UiAction -Name 'Lancer' -Action { Invoke-Launch } })

    $window.Add_ContentRendered({
            Invoke-UiAction -Name 'relevé du poste' -Action { Initialize-MachineView }
        })
    $window.Add_Closed({
            Stop-UiPump
            foreach ($section in (Get-UiSection)) {
                try { Invoke-UiSectionCallback -Section $section -Name Dispose | Out-Null } catch { Write-Verbose $_.Exception.Message }
            }
        })

    Start-UiPump -Log $Context.Log
    [void]$window.ShowDialog()
}

function Initialize-MachineView {
    <# Relevé du poste, export de l'inventaire, remplissage des sections. #>
    $context = $script:Context
    $snapshot = Get-MachineSnapshot -Context $context
    $snapshot.InventoryExport = Export-MachineInventory -Snapshot $snapshot -Context $context
    $script:Snapshot = $snapshot

    $shell = $script:Shell.Controls
    $shell.TxtPoste.Text = 'Poste détecté : {0} — {1}' -f $snapshot.Identity.Manufacturer, $snapshot.Identity.Model
    $shell.TxtOs.Text = $snapshot.Identity.OsLabel

    foreach ($section in (Get-UiSection)) {
        Invoke-UiSectionCallback -Section $section -Name OnSnapshot -Arguments @($snapshot, $context) | Out-Null
    }
    Update-UiState
}

function Get-CurrentSelection {
    <# Sélection courante : chaque section y écrit sa partie. #>
    $selection = New-Selection
    foreach ($section in (Get-UiSection)) {
        Invoke-UiSectionCallback -Section $section -Name GetSelection -Arguments @($selection) | Out-Null
    }
    return $selection
}

function Update-UiState {
    <# À appeler après tout changement : informe les sections (Refresh) puis met à jour Lancer. #>
    $selection = Get-CurrentSelection
    foreach ($section in (Get-UiSection)) {
        Invoke-UiSectionCallback -Section $section -Name Refresh -Arguments @($selection) | Out-Null
    }
    Update-LaunchState
}

function Update-LaunchState {
    <# Lancer est actif si le relevé est prêt et qu'aucune section ne le bloque ; sinon le premier motif est affiché. #>
    $shell = $script:Shell.Controls
    $reason = $null
    if (-not $script:Snapshot) { $reason = 'Grisé : détection du poste en cours' }
    else {
        foreach ($section in (Get-UiSection)) {
            $reason = Invoke-UiSectionCallback -Section $section -Name Validate
            if ($reason) { break }
        }
    }

    $shell.BtnGo.IsEnabled = (-not $reason)
    if ($reason) { $shell.TxtGoHint.Text = $reason }
    elseif ($script:Context.Mode -eq 'Simulation') { $shell.TxtGoHint.Text = 'Simulation : rien ne sera modifié' }
    else { $shell.TxtGoHint.Text = 'Aucun redémarrage automatique' }
}

function Invoke-Launch {
    <# Bouton Lancer : construit la sélection et la transmet au moteur (simulation à l'itération 0). #>
    $selection = Get-CurrentSelection
    [void](Invoke-SelectionSimulation -Selection $selection -Snapshot $script:Snapshot -Context $script:Context)
}

function Invoke-UiAction {
    <#
        Exécute le traitement d'un événement de l'interface : une erreur est journalisée au lieu
        de remonter dans la boucle de messages WPF (ce qui fermerait la fenêtre).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    try {
        & $Action
    } catch {
        Write-RunLog -Log $script:Context.Log -Level ERREUR -Message ("Erreur ({0}) : {1}" -f $Name, $_.Exception.Message)
    }
}

function Set-MemoText {
    param($TextBlock, [string[]]$Reminder)
    $TextBlock.Inlines.Clear()
    $title = New-Object System.Windows.Documents.Run('Mémo — fait à la main, hors outil : ')
    $title.FontWeight = [System.Windows.FontWeights]::SemiBold
    $TextBlock.Inlines.Add($title)
    $TextBlock.Inlines.Add((New-Object System.Windows.Documents.Run(($Reminder -join ' · '))))
}
