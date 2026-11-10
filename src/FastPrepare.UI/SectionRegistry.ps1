<#
    Registre des sections de la fenêtre. Une section = un fichier Sections/<Nom>Section.ps1
    (et en général un fragment Xaml/Sections/<Nom>.xaml) qui appelle Register-UiSection.
    MainWindow.ps1 ne connaît aucune section en particulier : il parcourt ce registre.

    Contrat des fonctions d'une section (toutes facultatives) :
      Initialize  param($Section, $Context)            branche les événements, génère les contrôles issus de la configuration
      OnSnapshot  param($Section, $Snapshot, $Context) remplit les listes quand le relevé du poste est prêt
      GetSelection param($Section, $Selection)         écrit SA partie de la Selection (FastPrepare.Core, New-Selection)
      Refresh     param($Section, $Selection)          réagit à un changement ailleurs dans la fenêtre
      Validate    param($Section)                      $null, ou le motif qui bloque le bouton Lancer
      Dispose     param($Section)                      libère ses ressources à la fermeture
    Chaque section reçoit .Controls (ses éléments nommés) et .State (son état propre).
#>

$script:UiSections = [ordered]@{}
# Liste triée mise en cache : Get-UiSection est appelé plusieurs fois à chaque clic.
$script:UiSectionsSorted = $null

function Register-UiSection {
    <# Enregistre une section. -Column : Left, Right ou Header (contrôles de la coquille, sans fragment). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][int]$Number,
        [Parameter(Mandatory)][ValidateSet('Left', 'Right', 'Header')][string]$Column,
        [string]$XamlFile,
        [scriptblock]$Initialize,
        [scriptblock]$OnSnapshot,
        [scriptblock]$GetSelection,
        [scriptblock]$Refresh,
        [scriptblock]$Validate,
        [scriptblock]$Dispose
    )
    if ($script:UiSections.Contains($Id)) { throw "Section d'interface enregistrée deux fois : '$Id'." }
    $script:UiSectionsSorted = $null
    $script:UiSections[$Id] = [pscustomobject]@{
        PSTypeName   = 'FastPrepare.UiSection'
        Id           = $Id
        Number       = $Number
        Column       = $Column
        XamlFile     = $XamlFile
        Initialize   = $Initialize
        OnSnapshot   = $OnSnapshot
        GetSelection = $GetSelection
        Refresh      = $Refresh
        Validate     = $Validate
        Dispose      = $Dispose
        Root         = $null
        Controls     = @{}
        State        = @{}
    }
}

function Get-UiSection {
    <# Une section par son identifiant, ou toutes, triées par numéro. #>
    [CmdletBinding()]
    param([string]$Id)
    if ($Id) {
        if (-not $script:UiSections.Contains($Id)) { throw "Section d'interface inconnue : '$Id'." }
        return $script:UiSections[$Id]
    }
    if ($null -eq $script:UiSectionsSorted) {
        $script:UiSectionsSorted = @($script:UiSections.Values | Sort-Object -Property Number)
    }
    return $script:UiSectionsSorted
}

function Invoke-UiSectionCallback {
    <#
        Appelle une fonction du contrat d'une section si elle est définie ; renvoie son résultat.
        Fonction simple (sans CmdletBinding) : appelée 30 à 40 fois à chaque clic.
    #>
    param($Section, [string]$Name, [object[]]$Arguments = @())
    $callback = $Section.$Name
    if (-not $callback) { return $null }
    return (& $callback $Section @Arguments)
}
