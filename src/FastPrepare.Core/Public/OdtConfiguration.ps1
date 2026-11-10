<#
    XML de l'Office Deployment Tool (cahier des charges, section 6).
    XML universel : 64 bits (configurable), langue MatchOS, une ExcludeApp par application
    décochée, aucune ligne Teams, aucune clé, aucun nom d'organisation. Fonctions pures.
#>

function Get-OfficeEdition {
    <# Édition de config.Office.Editions dont la clé est -Key ; erreur si elle n'existe pas. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$OfficeConfig,
        [Parameter(Mandatory)][string]$Key
    )
    foreach ($edition in @($OfficeConfig.Editions)) {
        if ($edition.Key -eq $Key) { return $edition }
    }
    throw "Édition Office inconnue : '$Key'."
}

function Test-OfficeEditionHasNoTeamsVariant {
    <# Vrai si l'édition propose une variante « sans Teams » (EEE). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)]$Edition)
    return [bool]($Edition.PSObject.Properties['NoTeamsProductId'] -and $Edition.NoTeamsProductId)
}

function Get-OfficeProductId {
    <# ID produit ODT de l'édition, variante sans Teams si demandée. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Edition,
        [switch]$WithoutTeams
    )
    if (-not $WithoutTeams) { return [string]$Edition.ProductId }
    if (-not (Test-OfficeEditionHasNoTeamsVariant -Edition $Edition)) {
        throw "L'édition '$($Edition.Key)' ne propose pas de variante sans Teams."
    }
    return [string]$Edition.NoTeamsProductId
}

function Get-ExcludedOfficeApp {
    <# Identifiants ExcludeApp : applications facultatives (config.Office.OptionalApps) non incluses, dans l'ordre de la configuration. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyCollection()][object[]]$OptionalApp,
        [AllowEmptyCollection()][string[]]$IncludedId
    )
    $included = @($IncludedId)
    return @(@($OptionalApp) | Where-Object { $_ -and ($included -notcontains $_.Id) } | ForEach-Object { [string]$_.Id })
}

function New-OdtInstallXml {
    <# Fichier configuration.xml d'installation (texte indenté de deux espaces, sans déclaration XML). #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$Channel,
        [AllowEmptyCollection()][string[]]$ExcludedApp = @(),
        [string]$Architecture = '64',
        [string]$Language = 'MatchOS'
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.NewLineChars = "`r`n"
    $settings.OmitXmlDeclaration = $true

    $buffer = New-Object System.Text.StringBuilder
    $writer = [System.Xml.XmlWriter]::Create($buffer, $settings)
    try {
        $writer.WriteStartElement('Configuration')

        $writer.WriteStartElement('Add')
        $writer.WriteAttributeString('OfficeClientEdition', $Architecture)
        $writer.WriteAttributeString('Channel', $Channel)
        $writer.WriteStartElement('Product')
        $writer.WriteAttributeString('ID', $ProductId)
        $writer.WriteStartElement('Language')
        $writer.WriteAttributeString('ID', $Language)
        $writer.WriteEndElement()
        foreach ($app in @($ExcludedApp)) {
            if (-not $app) { continue }
            $writer.WriteStartElement('ExcludeApp')
            $writer.WriteAttributeString('ID', $app)
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement()   # Product
        $writer.WriteEndElement()   # Add

        $writer.WriteStartElement('Updates')
        $writer.WriteAttributeString('Enabled', 'TRUE')
        $writer.WriteEndElement()

        $writer.WriteStartElement('Display')
        $writer.WriteAttributeString('Level', 'None')
        $writer.WriteAttributeString('AcceptEULA', 'TRUE')
        $writer.WriteEndElement()

        $writer.WriteStartElement('Property')
        $writer.WriteAttributeString('Name', 'FORCEAPPSHUTDOWN')
        $writer.WriteAttributeString('Value', 'TRUE')
        $writer.WriteEndElement()

        $writer.WriteEndElement()   # Configuration
    } finally {
        $writer.Close()
    }
    return $buffer.ToString()
}
