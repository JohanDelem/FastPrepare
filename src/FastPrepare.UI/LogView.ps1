<#
    Affichage du journal dans la fenêtre. Les lignes viennent de la file du journal
    (FastPrepare.Infrastructure, RunLog) ; elles sont vidées par la pompe (UiPump.ps1).
#>

$script:LogView = $null
$script:LogViewMaxLines = 5000
$script:LogLevelBrushKeys = @{
    'INFO'   = 'LogInfoBrush'
    'OK'     = 'LogOkBrush'
    'ERREUR' = 'LogErrorBrush'
    'ATTN'   = 'LogWarningBrush'
    'SIMU'   = 'LogSimulationBrush'
}

function Initialize-LogView {
    <# Associe la vue du journal à son RichTextBox (vidé de son paragraphe initial). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Controls.RichTextBox]$RichTextBox)
    $RichTextBox.Document.Blocks.Clear()
    $script:LogView = $RichTextBox
}

function Add-LogLine {
    <# Ajoute une ligne colorée selon son niveau ; ne garde que les 5 000 dernières à l'écran. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    if (-not $script:LogView) { return }
    $brushKey = $script:LogLevelBrushKeys[[string]$Entry.Level]
    if (-not $brushKey) { $brushKey = 'LogInfoBrush' }

    $paragraph = New-Object System.Windows.Documents.Paragraph
    $paragraph.Margin = New-Object System.Windows.Thickness(0)
    $run = New-Object System.Windows.Documents.Run([string]$Entry.Line)
    $run.Foreground = Get-ThemeResource -Key $brushKey
    $paragraph.Inlines.Add($run)

    $blocks = $script:LogView.Document.Blocks
    $blocks.Add($paragraph)
    while ($blocks.Count -gt $script:LogViewMaxLines) { [void]$blocks.Remove($blocks.FirstBlock) }
    $script:LogView.ScrollToEnd()
}
