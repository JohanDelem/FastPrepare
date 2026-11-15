<#
    Produit le livrable de l'outil : un dossier FastPrepare-<version> contenant le strict nécessaire
    à l'exécution (Lancer.cmd, Preparation.ps1, VERSION, config.json, software.json, src\, logos\,
    packages\ et un dossier logs\ vide), et, avec -Zip, l'archive FastPrepare-<version>.zip.
    Le même livrable se copie sur un support amovible, se dépose sur un partage ou se télécharge.
    Ni tests, ni documentation, ni journaux de développement.
    Si le dossier existe déjà : le code est remplacé, les journaux sont conservés, ainsi que le
    catalogue des logiciels (software.json, modifiable depuis l'onglet Réglages) :
    -ReplaceSoftwareCatalog le remplace par celui du dépôt.

    Usage : tools\Build-Release.ps1 -Destination D:\Livraisons [-Zip] [-ReplaceSoftwareCatalog] [-SkipChecks] [-PesterPath <chemin>]
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script console interactif : sortie colorée pour le développeur.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination,
    [switch]$Zip,
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

# Configuration validée avant toute copie ; ses avertissements sont affichés.
foreach ($module in 'FastPrepare.Core', 'FastPrepare.Infrastructure') {
    Import-Module (Join-Path $root "src\$module\$module.psd1") -Force
}
$version = Read-ToolVersion -Path (Join-Path $root 'VERSION')
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Fichier VERSION absent ou invalide (attendu : majeur.itération.correctif, ex. 1.13.0) : '$version'" }
$loaded = Read-AppConfig -Path (Join-Path $root 'config.json')
foreach ($warning in $loaded.Warnings) { Write-Host "[config.json] $warning" -ForegroundColor Yellow }
$catalogName = [string]$loaded.Config.SoftwareCatalog
$catalogInTool = -not [System.IO.Path]::IsPathRooted($catalogName)
if ($catalogInTool) {
    $catalog = Read-SoftwareCatalog -Path (Join-Path $root $catalogName)
    foreach ($warning in $catalog.Warnings) { Write-Host "[$catalogName] $warning" -ForegroundColor Yellow }
} else {
    Write-Host "[catalogue] Catalogue désigné par un chemin absolu ($catalogName) : il n'est pas copié dans le livrable." -ForegroundColor Yellow
}
if ($loaded.Config.Winget.PSObject.Properties['OfflineBundle'] -and $loaded.Config.Winget.OfflineBundle) {
    $bundle = Join-Path $root ([string]$loaded.Config.Winget.OfflineBundle)
    if (-not (Test-Path -LiteralPath $bundle -PathType Leaf)) {
        Write-Host "[packages] Paquet winget hors ligne absent ($bundle) : un poste sans winget ne pourra pas l'installer." -ForegroundColor Yellow
    }
}

if (-not $SkipChecks) {
    & (Join-Path $PSScriptRoot 'Invoke-Lint.ps1')
    if ($LASTEXITCODE) { throw 'Analyse statique en échec : livrable non produit.' }
    $testArguments = @{}
    if ($PesterPath) { $testArguments.PesterPath = $PesterPath }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-Tests.ps1') @testArguments
    if ($LASTEXITCODE) { throw 'Tests en échec : livrable non produit.' }
}

$name = "FastPrepare-$version"
$target = Join-Path $destinationFull $name
if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }

# Le code est remplacé en entier (aucun fichier obsolète ne subsiste) ; logs\ n'est jamais vidé.
$srcDestination = Join-Path $target 'src'
if (Test-Path -LiteralPath $srcDestination) { Remove-Item -LiteralPath $srcDestination -Recurse -Force }

foreach ($item in 'Lancer.cmd', 'Preparation.ps1', 'VERSION', 'config.json', 'src', 'logos', 'packages') {
    $source = Join-Path $root $item
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }
}
# Catalogue des logiciels : celui du livrable existant a pu être enrichi depuis l'onglet Réglages.
if ($catalogInTool) {
    $catalogDestination = Join-Path $target $catalogName
    if ((Test-Path -LiteralPath $catalogDestination) -and -not $ReplaceSoftwareCatalog) {
        Write-Host "[$catalogName] Catalogue déjà présent conservé (-ReplaceSoftwareCatalog pour le remplacer par celui du dépôt)." -ForegroundColor Yellow
    } else {
        Copy-Item -LiteralPath (Join-Path $root $catalogName) -Destination $catalogDestination -Force
    }
}
$logs = Join-Path $target 'logs'
if (-not (Test-Path -LiteralPath $logs)) { New-Item -ItemType Directory -Path $logs | Out-Null }

# Retire la marque « téléchargé depuis Internet » des scripts copiés.
Get-ChildItem -Path $target -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.cmd' | Unblock-File

$configHash = (Get-FileHash -LiteralPath (Join-Path $root 'config.json') -Algorithm SHA256).Hash
$commit = ''
try { $commit = (& git -C $root rev-parse --short HEAD 2>$null) } catch { $commit = '' }
Set-Content -LiteralPath (Join-Path $target 'BUILD.txt') -Encoding UTF8 -Value @(
    "Version     : $version",
    "Produit le  : $(Get-Date -Format 'dd/MM/yyyy HH:mm')",
    "Commit      : $commit",
    "config.json : SHA256 $configHash"
)
Write-Host "Livrable prêt : $target" -ForegroundColor Green

if ($Zip) {
    # L'archive ne contient jamais de journaux : ils portent des N/S, des MAC et des noms de comptes.
    $archive = Join-Path $destinationFull "$name.zip"
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ("FastPrepare-release-{0}" -f [guid]::NewGuid().ToString('N'))
    try {
        $stagingRoot = Join-Path $staging $name
        New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
        Get-ChildItem -LiteralPath $target -Force | Where-Object { $_.Name -ne 'logs' } |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stagingRoot -Recurse -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $archive)
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
    Write-Host "Archive prête : $archive" -ForegroundColor Green
}
