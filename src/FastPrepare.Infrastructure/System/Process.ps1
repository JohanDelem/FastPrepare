<#
    Point de passage unique vers un processus externe (règle §6 du plan d'architecture).
    Exécutable et arguments toujours séparés : jamais d'Invoke-Expression, jamais de chaîne shell.
    La commande effective, le code de sortie et la durée sont journalisés (niveau DEBUG).
#>

# Codes de sortie Windows Installer connus, traduits dans les messages d'erreur.
$script:KnownExitCodes = @{
    1602 = 'annulé par l''utilisateur'
    1603 = 'erreur fatale pendant l''installation'
    1618 = 'une autre installation est déjà en cours'
    1619 = 'paquet d''installation introuvable'
    1641 = 'succès, redémarrage lancé par l''installateur'
    3010 = 'succès, redémarrage nécessaire'
}

function Invoke-ExternalProcess {
    <#
        Lance -FilePath avec -ArgumentList et attend sa fin (au plus -TimeoutMinutes).
        Renvoie { ExitCode, RebootRequired, Duration, Output }.
        Erreur si le code de sortie n'est ni dans -SuccessExitCode ni dans -RebootExitCode.
        -CaptureOutput : récupère la sortie standard (fenêtre masquée).
        -Interactive   : la fenêtre du programme est affichée (assistant à suivre par le technicien).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [AllowEmptyString()][string]$ArgumentList = '',
        [string]$WorkingDirectory,
        [int]$TimeoutMinutes = 60,
        [int[]]$SuccessExitCode = @(0),
        [int[]]$RebootExitCode = @(3010, 1641),
        [switch]$CaptureOutput,
        [switch]$Interactive,
        $Log
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $ArgumentList
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    if ($Interactive) {
        $startInfo.UseShellExecute = $true
    } else {
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        if ($CaptureOutput) {
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        }
    }

    if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message ('Commande : "{0}" {1}' -f $FilePath, $ArgumentList) }
    $started = Get-Date
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
    } catch {
        throw ('Lancement impossible de « {0} » : {1}' -f $FilePath, $_.Exception.Message)
    }

    try {
        $outputTask = $null
        $errorTask = $null
        if ($CaptureOutput -and -not $Interactive) {
            # Lecture asynchrone : un tampon plein bloquerait le processus.
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
        }
        if (-not $process.WaitForExit([int][Math]::Min([int]::MaxValue, $TimeoutMinutes * 60000))) {
            throw ('« {0} » dépasse le délai de {1} min (processus laissé en cours, PID {2})' -f [System.IO.Path]::GetFileName($FilePath), $TimeoutMinutes, $process.Id)
        }
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $output = if ($outputTask) { $outputTask.Result + $errorTask.Result } else { '' }
    } finally {
        $process.Dispose()
    }

    $duration = (Get-Date) - $started
    if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message ('Code de sortie {0} en {1:N0} s : {2}' -f $exitCode, $duration.TotalSeconds, [System.IO.Path]::GetFileName($FilePath)) }

    $reboot = $RebootExitCode -contains $exitCode
    if (-not $reboot -and $SuccessExitCode -notcontains $exitCode) {
        $meaning = $script:KnownExitCodes[$exitCode]
        $detail = if ($meaning) { " ($meaning)" } else { '' }
        throw ('« {0} » : code de sortie {1}{2}' -f [System.IO.Path]::GetFileName($FilePath), $exitCode, $detail)
    }
    return [pscustomobject]@{ ExitCode = $exitCode; RebootRequired = $reboot; Duration = $duration; Output = $output }
}

function Get-SystemExecutablePath {
    <# Chemin absolu d'un exécutable de System32 (jamais résolu par le PATH). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    return (Join-Path ([Environment]::GetFolderPath('System')) $Name)
}
