<#
    winget (« Programme d'installation d'application »).
    Cahier des charges : vérifié au démarrage, réenregistré si absent
    (Add-AppxPackage -RegisterByFamilyName), sinon installé depuis un paquet .msixbundle de la clé.
#>

# Codes de sortie de winget traités comme un succès : paquet déjà installé, pas de mise à jour applicable.
$script:WingetAlreadyInstalledCodes = @(0x8A150061, 0x8A15002B)
# Codes de sortie de winget signalant un redémarrage nécessaire.
$script:WingetRebootCodes = @(0x8A150109, 3010, 1641)

function Test-Winget {
    <# Vrai si winget.exe est disponible pour le compte courant. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool](Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue)
}

function Assert-WingetAvailable {
    <#
        Garantit la présence de winget : déjà présent → rien ; sinon réenregistrement du paquet
        système (-FamilyName) ; sinon installation du paquet hors ligne (-OfflineBundle, avec les
        dépendances .appx/.msix du même dossier). Erreur explicite si rien ne fonctionne.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FamilyName,
        [Parameter(Mandatory)][string]$OfflineBundle,
        $Log
    )
    if (Test-Winget) { return }

    if ($Log) { Write-RunLog -Log $Log -Level ATTN -Message 'winget absent : réenregistrement du Programme d''installation d''application' }
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage $FamilyName -ErrorAction Stop
    } catch {
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Réenregistrement impossible : $($_.Exception.Message)" }
    }
    if (Test-Winget) {
        if ($Log) { Write-RunLog -Log $Log -Level OK -Message 'winget réenregistré' }
        return
    }

    if (-not (Test-Path -LiteralPath $OfflineBundle -PathType Leaf)) {
        throw "winget introuvable et paquet hors ligne absent : $OfflineBundle"
    }
    if ($Log) { Write-RunLog -Log $Log -Level ATTN -Message "Installation de winget depuis la clé : $OfflineBundle" }
    $dependencies = @(Get-ChildItem -LiteralPath (Split-Path -Path $OfflineBundle -Parent) -File |
            Where-Object { $_.Extension -in '.appx', '.msix' -and $_.FullName -ne $OfflineBundle } |
            ForEach-Object { $_.FullName })
    if ($dependencies.Count -gt 0) { Add-AppxPackage -Path $OfflineBundle -DependencyPath $dependencies -ErrorAction Stop }
    else { Add-AppxPackage -Path $OfflineBundle -ErrorAction Stop }

    if (-not (Test-Winget)) { throw 'winget toujours introuvable après installation du paquet hors ligne.' }
    if ($Log) { Write-RunLog -Log $Log -Level OK -Message 'winget installé depuis la clé' }
}

function Install-WingetPackage {
    <#
        winget install --id <Id> --exact --source <Source> --silent (accords acceptés, sans interaction),
        avec --override si fourni. « Déjà installé » est un succès. Renvoie { RebootRequired, AlreadyInstalled }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Source,
        [AllowEmptyString()][string]$Override,
        [int]$TimeoutMinutes = 60,
        $Log
    )

    $arguments = Get-WingetInstallArgument -Id $Id -Source $Source -Override $Override
    $wingetPath = (Get-Command -Name 'winget.exe' -ErrorAction Stop).Source
    $result = Invoke-ExternalProcess -FilePath $wingetPath -ArgumentList $arguments -TimeoutMinutes $TimeoutMinutes `
        -SuccessExitCode (@(0) + $script:WingetAlreadyInstalledCodes) -RebootExitCode $script:WingetRebootCodes -Log $Log
    return [pscustomobject]@{
        RebootRequired   = $result.RebootRequired
        AlreadyInstalled = ($script:WingetAlreadyInstalledCodes -contains $result.ExitCode)
    }
}

function Get-WingetInstallArgument {
    <# Ligne d'arguments de winget install (fonction séparée pour être vérifiée par les tests). #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Source,
        [AllowEmptyString()][string]$Override
    )
    if ($Id -match '[\s"]' -or $Source -match '[\s"]') { throw "Identifiant ou source winget invalide : '$Id' / '$Source'." }
    $arguments = 'install --id {0} --exact --source {1} --silent --accept-package-agreements --accept-source-agreements --disable-interactivity' -f $Id, $Source
    if ($Override) {
        if ($Override.Contains('"')) { throw "Option --override invalide (guillemet) : $Override" }
        $arguments += ' --override "{0}"' -f $Override
    }
    return $arguments
}
