<#
    Chargement des fichiers XAML et des ressources partagées.
#>

$script:ThemeLoaded = $false

function Initialize-WpfApplication {
    <#
        Crée l'objet Application WPF s'il n'existe pas encore (un seul par processus) et y fusionne
        le thème : les StaticResource des fragments XAML chargés séparément s'y résolvent.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ThemePath)

    if (-not [System.Windows.Application]::Current) {
        $application = New-Object System.Windows.Application
        $application.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    }
    if (-not $script:ThemeLoaded) {
        $theme = (Import-Xaml -Path $ThemePath).Root
        [System.Windows.Application]::Current.Resources.MergedDictionaries.Add($theme)
        $script:ThemeLoaded = $true
    }
}

function Import-Xaml {
    <# Charge un fichier XAML. Renvoie { Root, Controls } (Controls : éléments nommés, par nom). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $false
    $document.LoadXml([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8))

    $reader = New-Object System.Xml.XmlNodeReader $document
    try {
        $root = [System.Windows.Markup.XamlReader]::Load($reader)
    } catch {
        throw "XAML invalide ($Path) : $($_.Exception.Message)"
    }

    $controls = @{}
    if ($root -is [System.Windows.FrameworkElement]) {
        foreach ($node in $document.SelectNodes('//*[@Name]')) {
            $name = $node.GetAttribute('Name')
            $element = $root.FindName($name)
            if ($element) { $controls[$name] = $element }
        }
    }
    return [pscustomobject]@{ Root = $root; Controls = $controls }
}

$script:ThemeResourceCache = @{}

function Get-ThemeResource {
    <#
        Ressource nommée du thème (pinceau, style) ; erreur explicite si elle n'existe pas.
        Mise en cache, fonction simple : appelée pour chaque contrôle généré (une ligne par logiciel).
    #>
    param([string]$Key)
    $resource = $script:ThemeResourceCache[$Key]
    if ($null -ne $resource) { return $resource }
    $resource = [System.Windows.Application]::Current.TryFindResource($Key)
    if ($null -eq $resource) { throw "Ressource de thème introuvable : '$Key'." }
    $script:ThemeResourceCache[$Key] = $resource
    return $resource
}
