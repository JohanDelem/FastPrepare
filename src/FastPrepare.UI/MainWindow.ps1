<#
    Assemblage de la fenêtre : coquille, sections, pompe, bouton Lancer.
    Aucune règle métier ici : la validité vient des sections (Validate), les actions du moteur
    (FastPrepare.Application).
#>

$script:Context = $null
$script:Shell = $null
$script:Snapshot = $null
$script:Running = $false
$script:ProgressText = $null

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
    $shell.BdReal.Visibility = if ($Context.Mode -eq 'Real') { 'Visible' } else { 'Collapsed' }
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

    # Le relevé démarre une fois la fenêtre affichée et tourne en arrière-plan : la fenêtre reste réactive.
    $window.Add_ContentRendered({
            Invoke-UiAction -Name 'relevé du poste' -Action { Start-MachineView }
        })
    # Fermeture pendant une exécution : confirmation (l'action en cours irait à son terme).
    $window.Add_Closing({
            param($source, $closingArgs)
            if ($script:Running) {
                $answer = [System.Windows.MessageBox]::Show(
                    "Une exécution est en cours.`nFermer quand même ? L'action en cours ne sera pas annulée proprement.",
                    'Préparation de poste', 'YesNo', 'Warning')
                if ($answer -ne 'Yes') { $closingArgs.Cancel = $true }
                else { Write-RunLog -Log $script:Context.Log -Level ATTN -Message 'Fenêtre fermée pendant l''exécution : exécution interrompue.' }
            }
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

function Start-MachineView {
    <# Lance le relevé du poste en arrière-plan ; les sections sont remplies à son retour. #>
    $work = Start-MachineSnapshot -Context $script:Context
    Register-UiBackgroundWork -Work $work -OnCompleted {
        param($result)
        Complete-MachineView -Snapshot (@($result) | Select-Object -Last 1)
    } -OnFailed {
        param($message)
        Write-RunLog -Log $script:Context.Log -Level ERREUR -Message "Relevé du poste impossible : $message"
        $script:Shell.Controls.TxtPoste.Text = 'Détection du poste impossible (voir le journal)'
        $script:Shell.Controls.TxtGoHint.Text = 'Grisé : détection du poste impossible'
    }
}

function Complete-MachineView {
    <# Relevé terminé : en-tête, remplissage des sections, état du bouton Lancer. #>
    param([Parameter(Mandatory)]$Snapshot)
    $context = $script:Context
    $script:Snapshot = $Snapshot

    $shell = $script:Shell.Controls
    $shell.TxtPoste.Text = 'Poste détecté : {0} — {1}' -f $Snapshot.Identity.Manufacturer, $Snapshot.Identity.Model
    $shell.TxtOs.Text = $Snapshot.Identity.OsLabel

    foreach ($section in (Get-UiSection)) {
        try {
            Invoke-UiSectionCallback -Section $section -Name OnSnapshot -Arguments @($Snapshot, $context) | Out-Null
        } catch {
            Write-RunLog -Log $context.Log -Level ERREUR -Message ("Affichage de la section {0} impossible : {1}" -f $section.Number, $_.Exception.Message)
        }
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
    if ($script:Running) { $reason = if ($script:ProgressText) { $script:ProgressText } else { 'Exécution en cours…' } }
    elseif (-not $script:Snapshot) { $reason = 'Grisé : détection du poste en cours' }
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
    <#
        Bouton Lancer : sélection → plan d'exécution (le même pour la simulation et le réel) →
        confirmation en mode réel → exécution en arrière-plan, formulaire verrouillé jusqu'à la fin.
    #>
    $context = $script:Context
    $plan = New-ExecutionPlan -Selection (Get-CurrentSelection) -Snapshot $script:Snapshot -Context $context

    if ($context.Mode -ne 'Simulation') {
        $answer = [System.Windows.MessageBox]::Show(
            ("Lancer la préparation du poste ?`n`n{0}`n`nAucun redémarrage automatique." -f (Format-ExecutionPlanSummary -Plan $plan)),
            'Préparation de poste', 'YesNo', 'Question')
        if ($answer -ne 'Yes') { return }
    }

    Set-ExecutionLock -Locked $true
    $work = Start-ExecutionPlan -Plan $plan -Context $context
    Register-UiBackgroundWork -Work $work -OnCompleted {
        param($result)
        Set-ExecutionLock -Locked $false
    } -OnFailed {
        param($message)
        Write-RunLog -Log $script:Context.Log -Level ERREUR -Message "Exécution interrompue : $message"
        Set-ExecutionLock -Locked $false
    }
}

function Set-RunProgress {
    <# Avancement publié par le moteur (Publish-RunProgress) : barre et texte sous le bouton Lancer. #>
    param([int]$Current, [int]$Total, [string]$Label)
    if (-not $script:Running -or $Total -le 0) { return }
    $shell = $script:Shell.Controls
    $shell.PbRun.Maximum = $Total
    $shell.PbRun.Value = $Current - 1
    $short = if ($Label.Length -gt 70) { $Label.Substring(0, 67) + '…' } else { $Label }
    $script:ProgressText = 'Action {0} / {1} : {2}' -f $Current, $Total, $short
    $shell.TxtGoHint.Text = $script:ProgressText
}

function Set-ExecutionLock {
    <# Verrouille (ou libère) le formulaire pendant une exécution ; le journal reste lisible. #>
    param([bool]$Locked)
    $script:Running = $Locked
    $script:ProgressText = $null
    $shell = $script:Shell.Controls
    $shell.PbRun.Value = 0
    $shell.PbRun.Visibility = if ($Locked) { 'Visible' } else { 'Collapsed' }
    $shell.ColLeft.IsEnabled = -not $Locked
    $shell.ColRight.IsEnabled = -not $Locked
    Update-UiState
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
