<#
    Journal d'une exécution, utilisable depuis n'importe quel fil d'exécution.
    Chaque ligne est écrite dans le fichier (UTF-8 avec BOM) et publiée dans une file
    thread-safe que l'interface vide pour l'affichage. Le journal ne dépend pas de la fenêtre.
    Format d'une ligne (contrat, cf. docs/architecture_plan.md §8) : HH:mm:ss [NIVEAU] message
#>

$script:RunLogEncoding = New-Object System.Text.UTF8Encoding($true)

function New-RunLog {
    <#
        Choisit le dossier du journal (sonde d'écriture ; repli sur -FallbackFolder si la clé est
        en lecture seule) et prépare le fichier Journal_<hôte>_<horodatage>.log.
        Renvoie { FilePath, Folder, Queue, IsFallback, FileFailed }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$FallbackFolder,
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$Stamp
    )

    $isFallback = $false
    if (-not (Test-FolderWritable -Path $Folder)) {
        $isFallback = $true
        $Folder = $FallbackFolder
        if (-not (Test-Path -LiteralPath $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
    }

    $fileName = 'Journal_{0}_{1}.log' -f $HostName, $Stamp
    return [pscustomobject]@{
        PSTypeName = 'FastPrepare.RunLog'
        FilePath   = Join-Path $Folder $fileName
        Folder     = $Folder
        Queue      = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        IsFallback = $isFallback
        FileFailed = $false
        # Verrou partagé : le fil de l'interface et les runspaces d'arrière-plan écrivent dans le même fichier.
        SyncRoot   = New-Object object
    }
}

function Write-RunLog {
    <#
        Écrit une ligne dans le fichier et la publie dans la file (sauf DEBUG : fichier seulement).
        Un échec d'écriture du fichier est signalé une fois dans la file, puis l'écriture fichier
        est suspendue : plus d'échec silencieux.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Log,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet('INFO', 'OK', 'ERREUR', 'ATTN', 'SIMU', 'DEBUG')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message

    if (-not $Log.FileFailed) {
        [System.Threading.Monitor]::Enter($Log.SyncRoot)
        try {
            # UTF-8 avec BOM : le préambule n'est écrit qu'à la création du fichier.
            [System.IO.File]::AppendAllText($Log.FilePath, $line + "`r`n", $script:RunLogEncoding)
        } catch {
            if (-not $Log.FileFailed) {
                $Log.FileFailed = $true
                $warning = '{0} [ATTN] Écriture du journal impossible ({1}) : {2}' -f (Get-Date -Format 'HH:mm:ss'), $Log.FilePath, $_.Exception.Message
                $Log.Queue.Enqueue([pscustomobject]@{ Level = 'ATTN'; Line = $warning })
            }
        } finally {
            [System.Threading.Monitor]::Exit($Log.SyncRoot)
        }
    }

    if ($Level -ne 'DEBUG') {
        $Log.Queue.Enqueue([pscustomobject]@{ Level = $Level; Line = $line })
    }
}

function Receive-RunLogEntry {
    <# Vide la file : renvoie les entrées { Level, Line } publiées depuis le dernier appel. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Log)

    $entries = New-Object System.Collections.Generic.List[object]
    $entry = $null
    while ($Log.Queue.TryDequeue([ref]$entry)) { $entries.Add($entry) }
    return $entries.ToArray()
}

function Test-FolderWritable {
    param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null }
        $probe = Join-Path $Path ('.ecriture-{0}' -f [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $probe -Value 'ok' -ErrorAction Stop
        Remove-Item -LiteralPath $probe -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}
