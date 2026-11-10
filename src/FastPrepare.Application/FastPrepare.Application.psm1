<#
    Chargeur du module : charge les fichiers communs (registre et ordre des étapes, plan, moteur),
    puis chaque étape (Steps\*.step.ps1), qui s'enregistre au chargement ; vérifie enfin que le
    catalogue est cohérent avec l'ordre d'exécution (Assert-StepCatalog).
#>
$ErrorActionPreference = 'Stop'

foreach ($file in (Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' | Sort-Object -Property Name)) {
    . $file.FullName
}
foreach ($file in (Get-ChildItem -Path (Join-Path $PSScriptRoot 'Steps') -Filter '*.step.ps1' | Sort-Object -Property Name)) {
    . $file.FullName
}
Assert-StepCatalog
