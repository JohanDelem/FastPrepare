<#
    Catalogue des étapes d'exécution. Une étape = un fichier Steps/<Nom>.step.ps1 qui appelle
    Register-Step une fois. Contrat :
      Plan    param($Selection, $Snapshot, $Context)
              renvoie zéro, une ou plusieurs actions (New-StepAction) et éventuellement des
              avertissements (New-PlanWarning). Aucun effet de bord. Zéro action = étape non cochée.
      Invoke  param($Action, $Context)
              exécute UNE action par les fonctions de FastPrepare.Infrastructure ; lève une erreur
              en cas d'échec ; peut renvoyer { RebootRequired = $true }. Ne teste jamais le mode
              (simulation ou réel) : seul le moteur le connaît. Facultatif tant que l'étape n'est
              pas implémentée en mode réel.
#>

$script:RegisteredSteps = @{}

function Register-Step {
    <# Enregistre une étape. Son rang d'exécution vient de StepOrder.ps1, pas d'ici. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][int]$Section,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$Plan,
        [scriptblock]$Invoke
    )
    if ($script:RegisteredSteps.ContainsKey($Id)) { throw "Étape enregistrée deux fois : '$Id'." }
    $script:RegisteredSteps[$Id] = [pscustomobject]@{
        PSTypeName = 'FastPrepare.Step'
        Id         = $Id
        Section    = $Section
        Title      = $Title
        Plan       = $Plan
        Invoke     = $Invoke
    }
}

function Get-RegisteredStep {
    <# Une étape par son identifiant, ou le catalogue complet (table Id → étape). #>
    [CmdletBinding()]
    param([string]$Id)
    if ($Id) {
        if (-not $script:RegisteredSteps.ContainsKey($Id)) { throw "Étape inconnue : '$Id'." }
        return $script:RegisteredSteps[$Id]
    }
    return $script:RegisteredSteps
}

function Assert-StepCatalog {
    <#
        Chaque étape enregistrée figure exactement une fois dans l'ordre d'exécution, et
        réciproquement. Appelée au chargement du module : un oubli échoue au démarrage.
    #>
    [CmdletBinding()]
    param()
    $order = @(Get-StepOrder)
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($id in ($order | Group-Object | Where-Object Count -GT 1 | ForEach-Object Name)) {
        $problems.Add("'$id' figure plusieurs fois dans StepOrder.ps1")
    }
    foreach ($id in $order) {
        if (-not $script:RegisteredSteps.ContainsKey($id)) { $problems.Add("'$id' est dans StepOrder.ps1 mais aucune étape ne l'enregistre") }
    }
    foreach ($id in $script:RegisteredSteps.Keys) {
        if ($order -notcontains $id) { $problems.Add("l'étape '$id' est enregistrée mais absente de StepOrder.ps1") }
    }
    if ($problems.Count -gt 0) { throw ("Catalogue d'étapes incohérent :`n- " + ($problems -join "`n- ")) }
}

function New-StepAction {
    <#
        Action produite par le Plan d'une étape.
        -Label       : ligne du journal (ce qui sera fait, commande comprise) ;
        -Parameters  : données nécessaires à Invoke (aucun objet WPF, aucun scriptblock) ;
        -Details     : lignes complémentaires journalisées sous l'action (ex. XML ODT) ;
        -Interactive : l'action ouvre une fenêtre que le technicien doit suivre (assistant).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [hashtable]$Parameters = @{},
        [string[]]$Details = @(),
        [switch]$Interactive
    )
    return [pscustomobject]@{
        PSTypeName  = 'FastPrepare.StepAction'
        Label       = $Label
        Parameters  = $Parameters
        Details     = @($Details)
        Interactive = [bool]$Interactive
        StepId      = $null
        StepNumber  = 0
        Section     = 0
        Index       = 0
    }
}

function New-PlanWarning {
    <# Avertissement produit par le Plan d'une étape (choix sans effet, cas non couvert…). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    return [pscustomobject]@{ PSTypeName = 'FastPrepare.PlanWarning'; Message = $Message }
}
