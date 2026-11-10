<#
    winget (« Programme d'installation d'application »).
    Cahier des charges : vérifié au démarrage, réenregistré si absent
    (Add-AppxPackage -RegisterByFamilyName), sinon installé depuis un paquet .msixbundle de la clé.
    Tous les appels à winget passent par Invoke-Winget, qui répare une fois une source inutilisable
    (itération 10, DEC20).
#>

# Codes de sortie de winget traités comme un succès : paquet déjà installé, pas de mise à jour applicable.
$script:WingetAlreadyInstalledCodes = @(0x8A150061, 0x8A15002B)
# Codes de sortie de winget signalant un redémarrage nécessaire.
$script:WingetRebootCodes = @(0x8A150109, 3010, 1641)
# « Aucun paquet ne correspond » (APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND, 0x8A150014).
$script:WingetNoPackageFound = -1978335212
# « Données requises par la source manquantes » (APPINSTALLER_CLI_ERROR_SOURCE_DATA_MISSING, 0x8A15000F) :
# source jamais initialisée ou abîmée pour le compte qui exécute l'outil.
$script:WingetSourceDataMissing = -1978335217
# Terme recherché pour vérifier qu'une source s'ouvre : il ne correspond à aucun paquet.
$script:WingetSourceProbeQuery = 'fastprepare-sonde-source'

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
        [AllowEmptyString()][string]$Version,
        # Portée d'installation (machine, user ; vide = choix de winget).
        [ValidateSet('', 'machine', 'user')][string]$Scope = '',
        [int]$TimeoutMinutes = 60,
        # Réparation de la source (Get-WingetSourceRepair, FastPrepare.Application) ; facultative.
        $SourceRepair,
        $Log
    )

    $arguments = Get-WingetInstallArgument -Id $Id -Source $Source -Override $Override -Version $Version -Scope $Scope
    $result = Invoke-Winget -ArgumentList $arguments -TimeoutMinutes $TimeoutMinutes `
        -SuccessExitCode (@(0) + $script:WingetAlreadyInstalledCodes) -RebootExitCode $script:WingetRebootCodes -SourceRepair $SourceRepair -Log $Log
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
        [AllowEmptyString()][string]$Override,
        [AllowEmptyString()][string]$Version,
        [ValidateSet('', 'machine', 'user')][string]$Scope = ''
    )
    if ($Id -match '[\s"]' -or $Source -match '[\s"]') { throw "Identifiant ou source winget invalide : '$Id' / '$Source'." }
    if ($Version -and $Version -notmatch '^[0-9][0-9A-Za-z.\-]*$') { throw "Version winget invalide : '$Version'." }
    $arguments = 'install --id {0} --exact --source {1} --silent --accept-package-agreements --accept-source-agreements --disable-interactivity' -f $Id, $Source
    if ($Version) { $arguments += " --version $Version" }
    if ($Scope) { $arguments += " --scope $Scope" }
    if ($Override) {
        if ($Override.Contains('"')) { throw "Option --override invalide (guillemet) : $Override" }
        $arguments += ' --override "{0}"' -f $Override
    }
    return $arguments
}

function Get-WingetPackageVersion {
    <#
        Version qu'installerait winget pour ce paquet (winget show). Nécessaire pour choisir le runtime
        .NET de Dell Command Update avant de l'installer. Analyse tolérante à la langue de winget.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Source,
        # Réparation de la source (Get-WingetSourceRepair, FastPrepare.Application) ; facultative.
        $SourceRepair,
        $Log
    )
    if ($Id -match '[\s"]' -or $Source -match '[\s"]') { throw "Identifiant ou source winget invalide : '$Id' / '$Source'." }
    $result = Invoke-Winget -ArgumentList ('show --id {0} --exact --source {1} --accept-source-agreements --disable-interactivity' -f $Id, $Source) `
        -CaptureOutput -TimeoutMinutes 5 -SourceRepair $SourceRepair -Log $Log
    return (ConvertFrom-WingetShowOutput -Output $result.Output)
}

function ConvertFrom-WingetShowOutput {
    <# Extrait la version de la sortie de « winget show » (« Version: 5.7.0 » ou « Version : 5.7.0 »). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Output)
    $match = [regex]::Match([string]$Output, '(?m)^\s*Version\s*:\s*([0-9][0-9A-Za-z.\-]*)\s*$')
    if (-not $match.Success) { throw 'Version introuvable dans la sortie de « winget show ».' }
    return $match.Groups[1].Value
}

function Get-WingetPackageInfo {
    <#
        Nom, version et installateur d'un paquet par « winget show » : ne télécharge ni n'installe
        rien (test du catalogue des logiciels, DEC18). -Scope : installateur proposé pour cette
        portée (DEC22). Renvoie { Name, Version, InstallerFound, InstallerFile }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Source,
        [ValidateSet('', 'machine', 'user')][string]$Scope = '',
        # Réparation de la source (Get-WingetSourceRepair, FastPrepare.Application) ; facultative.
        $SourceRepair,
        $Log
    )
    if ($Id -match '[\s"]' -or $Source -match '[\s"]') { throw "Identifiant ou source winget invalide : '$Id' / '$Source'." }
    $arguments = 'show --id {0} --exact --source {1} --accept-source-agreements --disable-interactivity' -f $Id, $Source
    if ($Scope) { $arguments += " --scope $Scope" }
    $result = Invoke-Winget -ArgumentList $arguments `
        -SuccessExitCode @(0, $script:WingetNoPackageFound) -CaptureOutput -TimeoutMinutes 5 -SourceRepair $SourceRepair -Log $Log
    if ($result.ExitCode -eq $script:WingetNoPackageFound) { throw "paquet « $Id » introuvable dans la source « $Source »" }
    return (ConvertFrom-WingetShowDetail -Output $result.Output -Id $Id)
}

function ConvertFrom-WingetShowDetail {
    <#
        Sortie de « winget show », tolérante à la langue : nom (première ligne « Trouvé <nom> [<id>] »,
        « Found » en anglais), version (« Version: … »), installateur proposé. winget répond 0 même
        quand aucun installateur ne correspond à la portée demandée : sa présence est reconnue à
        sa ligne d'empreinte SHA-256 (64 caractères hexadécimaux), le fichier à la ligne de lien qui
        la précède.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Output, [Parameter(Mandatory)][string]$Id)
    $text = [string]$Output
    $nameMatch = [regex]::Match($text, ('(?m)^\s*\S+\s+(.+?)\s+\[{0}\]\s*$' -f [regex]::Escape($Id)))
    $installerFound = [regex]::IsMatch($text, '(?mi)^[^\r\n]*SHA256[^\r\n:]*:\s*[0-9a-f]{64}\s*$')
    $file = ''
    $urlMatch = [regex]::Match($text, '(?mi)^[^\r\n:]*:\s*(https://\S+)\s*\r?\n[^\r\n]*SHA256[^\r\n:]*:\s*[0-9a-f]{64}')
    if ($urlMatch.Success) { $file = ([System.Uri]$urlMatch.Groups[1].Value).Segments[-1] }
    return [pscustomobject]@{
        Name           = $(if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { '' })
        Version        = (ConvertFrom-WingetShowOutput -Output $text)
        InstallerFound = $installerFound
        InstallerFile  = $file
    }
}

function Test-WingetSource {
    <#
        Vérifie qu'une source winget s'ouvre pour le compte courant, sans rien télécharger : une
        recherche sans résultat (« aucun paquet ») prouve que la source répond. Une source
        inutilisable est réparée une fois (Invoke-Winget). Renvoie { Ready, Error }.
    #>
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9-]+$')][string]$Source = 'winget',
        # Réparation de la source (Get-WingetSourceRepair, FastPrepare.Application) ; facultative.
        $SourceRepair,
        $Log
    )
    try {
        [void](Invoke-Winget -ArgumentList ('search --query {0} --source {1} --accept-source-agreements --disable-interactivity' -f $script:WingetSourceProbeQuery, $Source) `
                -SuccessExitCode @(0, $script:WingetNoPackageFound) -CaptureOutput -TimeoutMinutes 3 -SourceRepair $SourceRepair -Log $Log)
        return [pscustomobject]@{ Ready = $true; Error = $null }
    } catch {
        return [pscustomobject]@{ Ready = $false; Error = $_.Exception.Message }
    }
}

function Invoke-Winget {
    <#
        Point de passage unique vers winget (par Invoke-ExternalProcess). Source inutilisable
        (0x8A15000F), réparations automatiques, chacune suivie d'un nouvel essai :
          1. « winget source update » ;
          2. installation du paquet de données de la source (Install-WingetSourcePackage), si
             -SourceRepair le désigne (DEC21).
        Si l'erreur persiste : message lisible avec la commande de réparation manuelle. Jamais
        de « winget source reset --force » automatique : il supprime aussi les sources ajoutées
        par une organisation (DEC20).
    #>
    param(
        [Parameter(Mandatory)][string]$ArgumentList,
        [int[]]$SuccessExitCode = @(0),
        [int[]]$RebootExitCode = @(3010, 1641),
        [switch]$CaptureOutput,
        [int]$TimeoutMinutes = 60,
        $SourceRepair,
        $Log
    )
    $wingetPath = (Get-Command -Name 'winget.exe' -ErrorAction Stop).Source
    $call = @{
        FilePath        = $wingetPath
        ArgumentList    = $ArgumentList
        SuccessExitCode = @($SuccessExitCode) + $script:WingetSourceDataMissing
        RebootExitCode  = $RebootExitCode
        CaptureOutput   = [bool]$CaptureOutput
        TimeoutMinutes  = $TimeoutMinutes
        Log             = $Log
    }
    $result = Invoke-ExternalProcess @call
    if ($result.ExitCode -ne $script:WingetSourceDataMissing) { return $result }

    $account = [Environment]::UserName
    # 1. Mise à jour des sources.
    if ($Log) { Write-RunLog -Log $Log -Level ATTN -Message "Source winget inutilisable pour le compte « $account » (0x8A15000F) : mise à jour des sources (winget source update) puis nouvel essai" }
    try {
        [void](Invoke-ExternalProcess -FilePath $wingetPath -ArgumentList 'source update --disable-interactivity' -CaptureOutput -TimeoutMinutes 5 -Log $Log)
    } catch {
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "winget source update : $($_.Exception.Message)" }
    }
    $result = Invoke-ExternalProcess @call
    if ($result.ExitCode -ne $script:WingetSourceDataMissing) {
        if ($Log) { Write-RunLog -Log $Log -Level OK -Message 'Source winget réparée par la mise à jour' }
        return $result
    }

    # 2. Installation du paquet de données de la source.
    $packageProblem = $null
    if ($SourceRepair -and $SourceRepair.PackageUrl) {
        try {
            Install-WingetSourcePackage -SourceRepair $SourceRepair -Log $Log
            $result = Invoke-ExternalProcess @call
            if ($result.ExitCode -ne $script:WingetSourceDataMissing) {
                if ($Log) { Write-RunLog -Log $Log -Level OK -Message 'Source winget réparée par l''installation de son paquet de données' }
                return $result
            }
            $packageProblem = 'paquet installé, source toujours inutilisable'
        } catch {
            $packageProblem = $_.Exception.Message
            if ($Log) { Write-RunLog -Log $Log -Level ATTN -Message "Installation du paquet de la source winget impossible : $packageProblem" }
        }
    } else {
        $packageProblem = 'non tentée (Winget.SourcePackage absent de config.json)'
    }

    $message = ("source winget inutilisable pour le compte « {0} » (0x8A15000F : données requises par la source manquantes), " +
        "malgré la mise à jour des sources (installation de son paquet de données : {1}). " +
        "À réparer dans une invite de commandes administrateur ouverte avec ce compte : winget source reset --force, puis winget source update.") -f $account, $packageProblem
    throw $message
}

function Install-WingetSourcePackage {
    <#
        Télécharge le paquet de données de la source winget (-SourceRepair.PackageUrl), exige une
        signature valide émise pour -SourceRepair.ExpectedSigner, l'installe pour le compte
        courant puis supprime le fichier. Erreur explicite à chaque étape.
    #>
    param(
        [Parameter(Mandatory)]$SourceRepair,
        $Log
    )
    if (-not $SourceRepair.ExpectedSigner) { throw 'éditeur attendu du paquet de la source absent : installation refusée' }
    $folder = [string]$SourceRepair.Folder
    $path = Join-Path $folder 'source.msix'
    if ($Log) { Write-RunLog -Log $Log -Level ATTN -Message ("Installation du paquet de données de la source winget ({0}, signature « {1} » vérifiée avant installation)" -f $SourceRepair.PackageUrl, $SourceRepair.ExpectedSigner) }
    try {
        [void](Save-RemoteFile -Url $SourceRepair.PackageUrl -Destination $path -Log $Log)
        Assert-TrustedExecutable -Path $path -ExpectedSigner ([string]$SourceRepair.ExpectedSigner)
        Add-AppxPackage -Path $path -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}
