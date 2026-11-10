<#
    Office Deployment Tool, partagé par la suppression (étape 3) et l'installation (étape 7).
    setup.exe est téléchargé depuis le lien de config.json et sa signature Microsoft vérifiée
    avant chaque utilisation.
#>

function Initialize-OdtFolder {
    <# Crée le dossier ODT et y place setup.exe (téléchargé si absent). Renvoie le chemin de setup.exe. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$SetupUrl,
        $Log
    )
    if (-not (Test-Path -LiteralPath $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
    $setup = Join-Path $Folder 'setup.exe'
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
        if ($Log) { Write-RunLog -Log $Log -Message "Téléchargement de l'Office Deployment Tool dans $Folder" }
        [void](Save-RemoteFile -Url $SetupUrl -Destination $setup -Log $Log)
    }
    Assert-TrustedExecutable -Path $setup -ExpectedSigner 'Microsoft'
    return $setup
}

function Invoke-Odt {
    <#
        Écrit le XML dans le dossier ODT (configuration-<nom>-<horodatage>.xml) et lance
        setup.exe /configure. Renvoie { RebootRequired, ConfigurationPath }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SetupPath,
        [Parameter(Mandatory)][string]$Xml,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Name,
        [int]$TimeoutMinutes = 90,
        $Log
    )
    $folder = Split-Path -Path $SetupPath -Parent
    $configuration = Join-Path $folder ('configuration-{0}-{1}.xml' -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [System.IO.File]::WriteAllText($configuration, $Xml, (New-Object System.Text.UTF8Encoding($false)))
    $result = Invoke-ExternalProcess -FilePath $SetupPath -ArgumentList ('/configure "{0}"' -f $configuration) -WorkingDirectory $folder -TimeoutMinutes $TimeoutMinutes -Log $Log
    return [pscustomobject]@{ RebootRequired = $result.RebootRequired; ConfigurationPath = $configuration }
}

function Get-OfficeClickToRunProduct {
    <#
        Produits Office Click-to-Run installés (ProductReleaseIds de la configuration Click-to-Run),
        ex. « O365BusinessRetail ». Liste vide si Office Click-to-Run n'est pas installé.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $configuration = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if (-not $configuration -or -not $configuration.PSObject.Properties['ProductReleaseIds']) { return @() }
    return @(([string]$configuration.ProductReleaseIds).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
