<#
    Chargeur du module : dot-source chaque fichier .ps1 du dossier (sous-dossiers compris).
    Les fonctions exportées sont listées explicitement dans le manifeste (.psd1).
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

foreach ($file in (Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' -Recurse | Sort-Object -Property FullName)) {
    . $file.FullName
}
