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

    $card = New-Object System.Windows.Controls.Primitives.ToggleButton
    $card.Style = Get-ThemeResource -Key 'Card'
    $card.Tag = $Key
    if ($IsLast) { $card.Margin = New-Object System.Windows.Thickness(0) }

    $panel = New-Object System.Windows.Controls.StackPanel

    if ($LogoPath -and (Test-Path -LiteralPath $LogoPath -PathType Leaf)) {
        try {
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.UriSource = New-Object System.Uri($LogoPath)
            $bitmap.EndInit()
            $image = New-Object System.Windows.Controls.Image
            $image.Height = 40
            $image.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
            $image.Source = $bitmap
            [void]$panel.Children.Add($image)
        } catch {
            if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Logo non chargé ($LogoPath) : $($_.Exception.Message)" }
        }
    }

    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = $Title
    $titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $titleBlock.TextAlignment = [System.Windows.TextAlignment]::Center
    $titleBlock.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    [void]$panel.Children.Add($titleBlock)

    if ($Subtitle) {
        $subtitleBlock = New-Object System.Windows.Controls.TextBlock
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

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($width in @('*', 170, 96)) {
        $column = New-Object System.Windows.Controls.ColumnDefinition
        if ($width -eq '*') { $column.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
        else { $column.Width = New-Object System.Windows.GridLength($width) }
        $grid.ColumnDefinitions.Add($column)
    }

    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $Software.Name
    $label.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $check = New-Object System.Windows.Controls.CheckBox
    $check.Content = $label
    $check.Tag = $Software
    $check.Margin = New-Object System.Windows.Thickness(10, 5, 8, 5)
    $check.ToolTip = if ($Software.Command) { '{0} : {1}' -f $Software.Method, $Software.Command } else { $Software.Method }
    [System.Windows.Controls.Grid]::SetColumn($check, 0)

    $publisher = New-Object System.Windows.Controls.TextBlock
    $publisher.Text = $Software.Publisher
    $publisher.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    $publisher.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $publisher.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $publisher.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    [System.Windows.Controls.Grid]::SetColumn($publisher, 1)

    $mark = New-Object System.Windows.Controls.TextBlock
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

    $border = New-Object System.Windows.Controls.Border
    $border.BorderBrush = Get-ThemeResource -Key 'BorderSubtleBrush'
    $border.BorderThickness = New-Object System.Windows.Thickness(0, 1, 0, 0)
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
    $check = New-Object System.Windows.Controls.CheckBox
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
