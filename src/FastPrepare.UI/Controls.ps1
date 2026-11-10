<#
    Fabriques des contrôles générés depuis la configuration ou le relevé du poste
    (cards, lignes de logiciels, cases à cocher) et comportements communs.
#>

function New-SelectableCard {
    <#
        Card sélectionnable (ToggleButton au style « Card ») : titre, sous-titre et logo facultatifs.
        Le logo n'est affiché que si le fichier existe et se charge.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Title,
        [string]$Subtitle,
        [string]$LogoPath,
        [switch]$IsLast,
        $Log
    )

    $card = [System.Windows.Controls.Primitives.ToggleButton]::new()
    $card.Style = Get-ThemeResource -Key 'Card'
    $card.Tag = $Key
    if ($IsLast) { $card.Margin = [System.Windows.Thickness]::new(0) }

    $panel = [System.Windows.Controls.StackPanel]::new()

    if ($LogoPath -and (Test-Path -LiteralPath $LogoPath -PathType Leaf)) {
        try {
            $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bitmap.BeginInit()
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.UriSource = [System.Uri]::new($LogoPath)
            $bitmap.EndInit()
            $image = [System.Windows.Controls.Image]::new()
            $image.Height = 40
            $image.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
            $image.Source = $bitmap
            [void]$panel.Children.Add($image)
        } catch {
            if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Logo non chargé ($LogoPath) : $($_.Exception.Message)" }
        }
    }

    $titleBlock = [System.Windows.Controls.TextBlock]::new()
    $titleBlock.Text = $Title
    $titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $titleBlock.TextAlignment = [System.Windows.TextAlignment]::Center
    $titleBlock.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    [void]$panel.Children.Add($titleBlock)

    if ($Subtitle) {
        $subtitleBlock = [System.Windows.Controls.TextBlock]::new()
        $subtitleBlock.Text = $Subtitle
        $subtitleBlock.Style = Get-ThemeResource -Key 'Hint'
        $subtitleBlock.TextAlignment = [System.Windows.TextAlignment]::Center
        [void]$panel.Children.Add($subtitleBlock)
    }

    $card.Content = $panel
    return $card
}

function New-SoftwareRow {
    <#
        Ligne de la liste des logiciels installés : case (nom), éditeur, désinstallation silencieuse.
        Renvoie { Element, CheckBox } ; la case porte le logiciel dans Tag.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Software)

    $grid = [System.Windows.Controls.Grid]::new()
    foreach ($width in @('*', 170, 96)) {
        $column = [System.Windows.Controls.ColumnDefinition]::new()
        if ($width -eq '*') { $column.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        else { $column.Width = [System.Windows.GridLength]::new($width) }
        $grid.ColumnDefinitions.Add($column)
    }

    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = $Software.Name
    $label.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $check = [System.Windows.Controls.CheckBox]::new()
    $check.Content = $label
    $check.Tag = $Software
    $check.Margin = [System.Windows.Thickness]::new(10, 5, 8, 5)
    $check.ToolTip = if ($Software.Command) { '{0} : {1}' -f $Software.Method, $Software.Command } else { $Software.Method }
    [System.Windows.Controls.Grid]::SetColumn($check, 0)

    $publisher = [System.Windows.Controls.TextBlock]::new()
    $publisher.Text = $Software.Publisher
    $publisher.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    $publisher.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $publisher.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $publisher.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    [System.Windows.Controls.Grid]::SetColumn($publisher, 1)

    $mark = [System.Windows.Controls.TextBlock]::new()
    $mark.FontWeight = [System.Windows.FontWeights]::SemiBold
    $mark.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    if ($Software.Silent) {
        $mark.Text = '✓ Oui'
        $mark.Foreground = Get-ThemeResource -Key 'SuccessBrush'
    } else {
        $mark.Text = '⚠ Non'
        $mark.Foreground = Get-ThemeResource -Key 'WarningBrush'
    }
    [System.Windows.Controls.Grid]::SetColumn($mark, 2)

    [void]$grid.Children.Add($check)
    [void]$grid.Children.Add($publisher)
    [void]$grid.Children.Add($mark)

    $border = [System.Windows.Controls.Border]::new()
    $border.BorderBrush = Get-ThemeResource -Key 'BorderSubtleBrush'
    $border.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
    $border.Child = $grid
    return [pscustomobject]@{ Element = $border; CheckBox = $check }
}

function New-CheckItem {
    <# Case à cocher simple, l'objet associé dans Tag. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Content,
        $Tag,
        [bool]$IsChecked = $false,
        [System.Windows.Thickness]$Margin
    )
    $check = [System.Windows.Controls.CheckBox]::new()
    $check.Content = $Content
    $check.Tag = $Tag
    $check.IsChecked = $IsChecked
    if ($PSBoundParameters.ContainsKey('Margin')) { $check.Margin = $Margin }
    return $check
}

function Set-ExclusiveSelection {
    <# Une seule card cochée par groupe : décoche les autres. Re-cliquer une card la désélectionne. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Card,
        [Parameter(Mandatory)]$Source
    )
    foreach ($other in $Card) {
        if (-not [object]::ReferenceEquals($other, $Source)) { $other.IsChecked = $false }
    }
}

function Get-CheckedCardKey {
    <# Clé (Tag) de la card cochée du groupe, ou $null. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyCollection()][object[]]$Card)
    foreach ($item in @($Card)) {
        if ($item.IsChecked) { return [string]$item.Tag }
    }
    return $null
}
