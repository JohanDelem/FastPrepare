<#
    Prépare une clé (ou un dossier) avec le strict nécessaire à l'exécution :
    Lancer.cmd, Preparation.ps1, config.json, software.json, src\, logos\, packages\ et un dossier
    logs\ vide. Ni tests, ni documentation, ni journaux de développement.
    Les journaux déjà présents sur la clé sont conservés, ainsi que son catalogue des logiciels
    (software.json, modifiable depuis l'onglet Réglages) : -ReplaceSoftwareCatalog le remplace
    par celui du dépôt.

    Usage : tools\Build-Usb.ps1 -Destination E:\FastPrepare [-ReplaceSoftwareCatalog] [-SkipChecks] [-PesterPath <chemin>]
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script console interactif : sortie colorée pour le développeur.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination,
    [switch]$ReplaceSoftwareCatalog,
    [switch]$SkipChecks,
    [string]$PesterPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# La destination ne doit pas être dans le dépôt (copie récursive de src\ dans lui-même).
$destinationFull = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\')
if ($destinationFull.StartsWith($root.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase) -or $destinationFull -ieq $root.TrimEnd('\')) {
    throw "Destination à l'intérieur du dépôt refusée : $destinationFull"
}

# Configuration validée avant toute copie ; ses avertissements (liens à renseigner…) sont affichés.
foreach ($module in 'FastPrepare.Core', 'FastPrepare.Infrastructure') {
    Import-Module (Join-Path $root "src\$module\$module.psd1") -Force
}
$loaded = Read-AppConfig -Path (Join-Path $root 'config.json')
foreach ($warning in $loaded.Warnings) { Write-Host "[config.json] $warning" -ForegroundColor Yellow }
$catalogName = [string]$loaded.Config.SoftwareCatalog
$catalog = Read-SoftwareCatalog -Path (Join-Path $root $catalogName)
foreach ($warning in $catalog.Warnings) { Write-Host "[$catalogName] $warning" -ForegroundColor Yellow }
$bundle = Join-Path $root ([string]$loaded.Config.Winget.OfflineBundle)
if (-not (Test-Path -LiteralPath $bundle -PathType Leaf)) {
    Write-Host "[packages] Paquet winget hors ligne absent ($bundle) : un poste sans winget ne pourra pas l'installer depuis la clé." -ForegroundColor Yellow
}

if (-not $SkipChecks) {
    & (Join-Path $PSScriptRoot 'Invoke-Lint.ps1')
    if ($LASTEXITCODE) { throw 'Analyse statique en échec : clé non préparée.' }
    $testArguments = @{}
    if ($PesterPath) { $testArguments.PesterPath = $PesterPath }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-Tests.ps1') @testArguments
    if ($LASTEXITCODE) { throw 'Tests en échec : clé non préparée.' }
}

if (-not (Test-Path -LiteralPath $Destination)) { New-Item -ItemType Directory -Path $Destination | Out-Null }

# Le code est remplacé en entier (aucun fichier obsolète ne subsiste) ; logs\ n'est jamais vidé.
$srcDestination = Join-Path $Destination 'src'
if (Test-Path -LiteralPath $srcDestination) { Remove-Item -LiteralPath $srcDestination -Recurse -Force }

foreach ($item in 'Lancer.cmd', 'Preparation.ps1', 'config.json', 'src', 'logos', 'packages') {
    $source = Join-Path $root $item
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $Destination -Recurse -Force
    }
}
# Catalogue des logiciels : celui de la clé a pu être enrichi depuis l'onglet Réglages.
$catalogDestination = Join-Path $Destination $catalogName
if ((Test-Path -LiteralPath $catalogDestination) -and -not $ReplaceSoftwareCatalog) {
    Write-Host "[$catalogName] Catalogue de la clé conservé (-ReplaceSoftwareCatalog pour le remplacer par celui du dépôt)." -ForegroundColor Yellow
} elseif (Test-Path -LiteralPath (Join-Path $root $catalogName)) {
    Copy-Item -LiteralPath (Join-Path $root $catalogName) -Destination $catalogDestination -Force
}
$logs = Join-Path $Destination 'logs'
if (-not (Test-Path -LiteralPath $logs)) { New-Item -ItemType Directory -Path $logs | Out-Null }

# Retire la marque « téléchargé depuis Internet » des scripts copiés.
Get-ChildItem -Path $Destination -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.cmd' | Unblock-File

$configHash = (Get-FileHash -LiteralPath (Join-Path $root 'config.json') -Algorithm SHA256).Hash
$commit = ''
try { $commit = (& git -C $root rev-parse --short HEAD 2>$null) } catch { $commit = '' }
Set-Content -LiteralPath (Join-Path $Destination 'VERSION.txt') -Encoding UTF8 -Value @(
    "Préparée le : $(Get-Date -Format 'dd/MM/yyyy HH:mm')",
    "Commit      : $commit",
    "config.json : SHA256 $configHash"
)
Write-Host "Clé prête : $Destination" -ForegroundColor Green
