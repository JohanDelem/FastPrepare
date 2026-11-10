<#
    Téléchargement anticipé de l'utilitaire constructeur (cahier des charges, section 5 :
    « Téléchargement lancé dès le clic, dépendances comprises »).

    Ce qui est préchargé : les éléments « download » (lien direct, ex. Lenovo Thin Installer),
    placés dans le cache ; et, pour un utilitaire à dépendance .NET (Dell), la version proposée par
    winget et le runtime correspondant sont résolus tout de suite, pour signaler un problème avant
    de lancer. Les paquets winget ne sont pas préchargés : winget install ne réutilise pas un dossier
    produit par winget download (décision DEC13 du plan d'architecture).
    Le cache est un simple dossier : l'étape 6 y reprend le fichier s'il est complet, sinon le
    télécharge elle-même. Aucun état n'est partagé entre la fenêtre et le moteur.
#>

function Get-PrefetchCachePath {
    <# Chemin du fichier d'un élément « download » dans le cache : <cache>\<marque>\<nom de fichier>. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$UtilityKey,
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)]$Context
    )
    $fileName = [System.IO.Path]::GetFileName([string]$Item.FileName)
    if (-not $fileName -or $fileName -ne [string]$Item.FileName) { throw "Nom de fichier invalide dans config.json : '$($Item.FileName)'." }
    return (Join-Path (Join-Path $Context.Paths.Cache $UtilityKey) $fileName)
}

function Get-PrefetchedItem {
    <# Fichier déjà préchargé (complet), ou $null. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$UtilityKey,
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)]$Context
    )
    $path = Get-PrefetchCachePath -UtilityKey $UtilityKey -Item $Item -Context $Context
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    return $null
}

function Test-PrefetchUseful {
    <# Vrai si l'utilitaire a quelque chose à précharger (lien direct renseigné, ou dépendance .NET). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$UtilityKey,
        [Parameter(Mandatory)]$Context
    )
    $utility = $Context.Config.Utilities.$UtilityKey
    $hasDownload = [bool](@($utility.Install) | Where-Object { $_.Type -eq 'download' -and $_.Url })
    $hasDotNet = $utility.PSObject.Properties['DotNet'] -and @($utility.DotNet).Count -gt 0
    return ($hasDownload -or $hasDotNet)
}

function Invoke-Prefetch {
    <#
        Précharge ce qui peut l'être pour l'utilitaire. Les erreurs sont journalisées (ATTN), jamais
        bloquantes : l'étape 6 refera le travail. Renvoie { UtilityKey, ToolVersion, DotNet, Files, Errors }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UtilityKey,
        [Parameter(Mandatory)]$Context
    )
    $log = $Context.Log
    $utility = $Context.Config.Utilities.$UtilityKey
    $result = [pscustomobject]@{ UtilityKey = $UtilityKey; ToolVersion = $null; DotNet = $null; Files = @(); Errors = @() }

    if ($utility.PSObject.Properties['DotNet'] -and @($utility.DotNet).Count -gt 0) {
        try {
            $resolution = Resolve-UtilityDotNetRequirement -UtilityKey $UtilityKey -Context $Context
            $result.ToolVersion = $resolution.ToolVersion
            $result.DotNet = $resolution.Requirement
            if ($resolution.Requirement) {
                Write-RunLog -Log $log -Message ('Préchargement : {0} {1} proposé par winget, runtime requis {2} ({3} à {4})' -f $utility.Tool, $resolution.ToolVersion, $resolution.Requirement.WingetId, $resolution.Requirement.MinVersion, $(if ($resolution.Requirement.MaxVersion) { $resolution.Requirement.MaxVersion } else { '…' }))
            }
        } catch {
            $result.Errors += $_.Exception.Message
            Write-RunLog -Log $log -Level ATTN -Message ("Préchargement {0} : version ou runtime .NET non résolu ({1}), nouvel essai à l'exécution" -f $utility.Tool, $_.Exception.Message)
        }
    }

    foreach ($item in @($utility.Install)) {
        if ($item.Type -ne 'download' -or -not $item.Url) { continue }
        try {
            $target = Get-PrefetchCachePath -UtilityKey $UtilityKey -Item $item -Context $Context
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                [void](Save-RemoteFile -Url $item.Url -Destination $target -Sha256 ([string]$item.Sha256) -Log $log)
            }
            $result.Files += $target
            Write-RunLog -Log $log -Level OK -Message "Préchargement : $($item.FileName) prêt ($target)"
        } catch {
            $result.Errors += $_.Exception.Message
            Write-RunLog -Log $log -Level ATTN -Message ("Préchargement de {0} impossible ({1}), nouvel essai à l'exécution" -f $item.FileName, $_.Exception.Message)
        }
    }
    return $result
}

function Start-Prefetch {
    <# Lance Invoke-Prefetch en arrière-plan. Renvoie le travail. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UtilityKey,
        [Parameter(Mandatory)]$Context
    )
    return Start-BackgroundWork -Name "prechargement-$UtilityKey" -ModulePath $Context.ModulePaths -Argument @($UtilityKey, $Context) -ScriptBlock {
        param($UtilityKey, $Context)
        Invoke-Prefetch -UtilityKey $UtilityKey -Context $Context
    }
}

function Resolve-UtilityDotNetRequirement {
    <#
        Version de l'utilitaire proposée par winget (premier élément winget de Install), puis entrée
        DotNet correspondante (Select-DotNetRequirement, FastPrepare.Core).
        Renvoie { ToolVersion, Requirement, IsExactMatch }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UtilityKey,
        [Parameter(Mandatory)]$Context
    )
    $utility = $Context.Config.Utilities.$UtilityKey
    $wingetItem = @($utility.Install) | Where-Object { $_.Type -eq 'winget' } | Select-Object -First 1
    if (-not $wingetItem) { throw "aucun paquet winget pour $($utility.Tool) : version introuvable" }
    Assert-WingetAvailable -FamilyName $Context.Config.Winget.FamilyName -OfflineBundle $Context.Paths.WingetBundle -Log $Context.Log
    $toolVersion = Get-WingetPackageVersion -Id $wingetItem.Id -Source $wingetItem.Source -Log $Context.Log
    $selection = Select-DotNetRequirement -ToolVersion $toolVersion -Requirement @($utility.DotNet)
    return [pscustomobject]@{
        ToolVersion  = $toolVersion
        Requirement  = if ($selection) { $selection.Requirement } else { $null }
        IsExactMatch = if ($selection) { $selection.IsExactMatch } else { $false }
    }
}
