<#
    Chargeur du module d'interface : charge d'abord les fichiers communs (registre des sections,
    fabriques de contrôles, fenêtre), puis chaque section, qui s'enregistre au chargement.
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

foreach ($file in (Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' | Sort-Object -Property Name)) {
    . $file.FullName
}
foreach ($file in (Get-ChildItem -Path (Join-Path $PSScriptRoot 'Sections') -Filter '*.ps1' | Sort-Object -Property Name)) {
    . $file.FullName
}
