<#
    Travaux d'arrière-plan : seul endroit qui crée des runspaces (règle §6 du plan d'architecture).
    Un travail tourne dans un runspace séparé qui importe les modules demandés par chemin absolu ;
    le fil de l'interface n'attend jamais : il vient vérifier la fin (Test-BackgroundWorkCompleted)
    puis récupérer le résultat (Receive-BackgroundWork).

    Les objets échangés ne sont pas sérialisés (même processus) : le travail reçoit le contexte
    (dont la file du journal, thread-safe) et renvoie des objets directement utilisables.
    Le bloc de script est transmis sous forme de texte : un scriptblock reste lié au runspace qui
    l'a créé et ne doit pas être exécuté depuis un autre fil.
#>

function Start-BackgroundWork {
    <#
        Lance -ScriptBlock dans un nouveau runspace (MTA) avec les modules -ModulePath importés.
        Les -Argument sont passés dans l'ordre aux paramètres du bloc.
        Renvoie un descripteur { Name, PowerShell, Runspace, AsyncResult, StartedAt }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$Argument = @(),
        [string[]]$ModulePath = @()
    )

    $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $state.ApartmentState = [System.Threading.ApartmentState]::MTA
    $state.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $state.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('ErrorActionPreference', 'Stop', $null)))
    foreach ($path in $ModulePath) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Module introuvable pour le travail '$Name' : $path" }
        [void]$state.ImportPSModule([string[]]@($path))
    }

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
    $runspace.Name = "FastPrepare-$Name"
    $runspace.Open()

    $powershell = [System.Management.Automation.PowerShell]::Create()
    $powershell.Runspace = $runspace
    [void]$powershell.AddScript($ScriptBlock.ToString(), $true)
    foreach ($value in $Argument) { [void]$powershell.AddArgument($value) }

    return [pscustomobject]@{
        PSTypeName  = 'FastPrepare.BackgroundWork'
        Name        = $Name
        PowerShell  = $powershell
        Runspace    = $runspace
        AsyncResult = $powershell.BeginInvoke()
        StartedAt   = Get-Date
    }
}

function Test-BackgroundWorkCompleted {
    <# Vrai quand le travail est terminé (succès ou erreur). Ne bloque jamais. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)]$Work)
    return [bool]$Work.AsyncResult.IsCompleted
}

function Receive-BackgroundWork {
    <#
        Résultat d'un travail terminé, puis libération du runspace.
        Une erreur bloquante du travail est relevée ici, avec le nom du travail.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Work)

    try {
        $output = $Work.PowerShell.EndInvoke($Work.AsyncResult)
        if ($Work.PowerShell.HadErrors -and $Work.PowerShell.Streams.Error.Count -gt 0 -and $output.Count -eq 0) {
            throw $Work.PowerShell.Streams.Error[0].Exception
        }
        return @($output | ForEach-Object { $_ })
    } catch {
        $exception = $_.Exception
        while ($exception.InnerException -and $exception -is [System.Management.Automation.MethodInvocationException]) {
            $exception = $exception.InnerException
        }
        throw ("Travail d'arrière-plan '{0}' en échec : {1}" -f $Work.Name, $exception.Message)
    } finally {
        Close-BackgroundWork -Work $Work
    }
}

function Stop-BackgroundWork {
    <# Demande l'arrêt d'un travail en cours sans attendre (fermeture de la fenêtre). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Work)
    try {
        if (-not $Work.AsyncResult.IsCompleted) { [void]$Work.PowerShell.BeginStop($null, $null) }
        else { Close-BackgroundWork -Work $Work }
    } catch {
        Write-Verbose ("Arrêt du travail '{0}' : {1}" -f $Work.Name, $_.Exception.Message)
    }
}

function Close-BackgroundWork {
    param($Work)
    if ($Work.PowerShell) { $Work.PowerShell.Dispose() }
    if ($Work.Runspace) { $Work.Runspace.Dispose() }
}
