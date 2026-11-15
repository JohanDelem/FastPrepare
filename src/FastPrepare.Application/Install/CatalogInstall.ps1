<#
    Installation d'une entrée du catalogue (software.json) : le seul chemin de code qui installe
    un paquet winget ou un lien direct, outil du constructeur compris (DEC26).
    L'entrée du catalogue est recopiée dans l'action : l'exécution ne dépend pas d'une
    modification ultérieure du catalogue.
#>

function Get-CatalogInstallAction {
    <#
        Actions du plan pour les entrées cochées, dans l'ordre du catalogue. Une entrée qui porte
        une dépendance .NET (champ DotNet) produit d'abord l'action de la dépendance : la version
        de l'outil proposée par winget n'est connue qu'à l'exécution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Selection,
        [Parameter(Mandatory)]$Context
    )
    $selected = @($Selection.Catalog.Ids)
    foreach ($software in @($Context.SoftwareCatalog)) {
        if ($selected -notcontains $software.Id) { continue }
        if (@($software.DotNet).Count -gt 0) {
            New-StepAction -Label ('{0} : dépendance, runtime .NET Desktop adapté à la version proposée par winget' -f $software.Label) -Parameters @{
                Kind = 'DotNetDependency'; Software = $software
            }
        }
        New-StepAction -Label ('{0} : {1}' -f $software.Label, (Format-SoftwareInstallCommand -Entry $software)) -Parameters @{
            Kind = 'CatalogInstall'; Software = $software
        }
    }
}

function Invoke-CatalogInstall {
    <# Installe une entrée : winget, ou téléchargement vérifié (empreinte, signature) puis lancement silencieux. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Software,
        [Parameter(Mandatory)]$Context
    )
    $install = $Software.Install
    $log = $Context.Log
    switch ([string]$install.Type) {
        'winget' {
            Assert-WingetAvailable -FamilyName $Context.Config.Winget.FamilyName -OfflineBundle $Context.Paths.WingetBundle -Log $log
            $result = Install-WingetPackage -Id $install.Id -Source $install.Source -Override ([string]$install.Override) -Scope ([string]$install.Scope) -SourceRepair (Get-WingetSourceRepair -Context $Context) -Log $log
            if ($result.AlreadyInstalled) { Write-RunLog -Log $log -Message ('{0} : déjà installé' -f $Software.Label) }
            return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
        }
        'download' {
            $folder = Join-Path $Context.Paths.Cache $Software.Id
            if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
            $path = Save-RemoteFile -Url $install.Url -Destination (Join-Path $folder $install.FileName) -Sha256 ([string]$install.Sha256) -Log $log
            Assert-TrustedExecutable -Path $path -ExpectedSigner ([string]$install.ExpectedSigner)
            if ($install.FileName -match '\.msi$') {
                $arguments = ('/i "{0}" /qn /norestart {1}' -f $path, $install.Arguments).Trim()
                $result = Invoke-ExternalProcess -FilePath (Get-SystemExecutablePath -Name 'msiexec.exe') -ArgumentList $arguments -TimeoutMinutes 60 -Log $log
            } else {
                $result = Invoke-ExternalProcess -FilePath $path -ArgumentList ([string]$install.Arguments) -TimeoutMinutes 60 -Log $log
            }
            return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
        }
        default { throw "type d'installation inconnu : '$($install.Type)'" }
    }
}

function Invoke-CatalogDotNetDependency {
    <# Dépendance .NET d'une entrée : résolue selon la version de l'outil proposée par winget, puis garantie. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Software,
        [Parameter(Mandatory)]$Context
    )
    $log = $Context.Log
    $resolution = Resolve-SoftwareDotNetRequirement -Software $Software -Context $Context
    $requirement = $resolution.Requirement
    if (-not $requirement) {
        Write-RunLog -Log $log -Level ATTN -Message ('{0} {1} : aucune entrée DotNet du catalogue ne s''applique, aucun runtime installé' -f $Software.Label, $resolution.ToolVersion)
        return
    }
    if (-not $resolution.IsExactMatch) {
        Write-RunLog -Log $log -Level ATTN -Message ('{0} {1} absent du catalogue (DotNet) : règle de la version {2} appliquée' -f $Software.Label, $resolution.ToolVersion, $requirement.ToolVersion)
    }
    Install-DotNetRequirement -Requirement $requirement -ToolLabel ('{0} {1}' -f $Software.Label, $resolution.ToolVersion) -Context $Context
}

function Resolve-SoftwareDotNetRequirement {
    <#
        Version de l'outil proposée par winget, puis entrée DotNet correspondante
        (Select-DotNetRequirement, FastPrepare.Core). Renvoie { ToolVersion, Requirement, IsExactMatch }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Software,
        [Parameter(Mandatory)]$Context
    )
    $install = $Software.Install
    if ([string]$install.Type -ne 'winget') { throw "aucun paquet winget pour $($Software.Label) : version introuvable" }
    Assert-WingetAvailable -FamilyName $Context.Config.Winget.FamilyName -OfflineBundle $Context.Paths.WingetBundle -Log $Context.Log
    $toolVersion = Get-WingetPackageVersion -Id $install.Id -Source $install.Source -SourceRepair (Get-WingetSourceRepair -Context $Context) -Log $Context.Log
    $selection = Select-DotNetRequirement -ToolVersion $toolVersion -Requirement @($Software.DotNet)
    return [pscustomobject]@{
        ToolVersion  = $toolVersion
        Requirement  = if ($selection) { $selection.Requirement } else { $null }
        IsExactMatch = if ($selection) { $selection.IsExactMatch } else { $false }
    }
}

function Install-DotNetRequirement {
    <#
        Garantit un runtime .NET Desktop dans la plage requise. Déjà présent → rien. Sinon installation
        par winget, à la version maximale de la plage si elle est bornée (un runtime trop récent fait
        échouer certains outils), puis vérification. Un runtime plus récent déjà présent est signalé.
    #>
    param($Requirement, [string]$ToolLabel, $Context)
    $log = $Context.Log
    $min = [string]$Requirement.MinVersion
    $max = [string]$Requirement.MaxVersion
    $major = ([version]$min).Major

    $installed = @(Get-DotNetDesktopRuntimeVersion)
    $sameMajorNewer = @($installed | Where-Object { $max -and ([version]$_).Major -eq $major -and -not (Test-VersionInRange -Version $_ -MinVersion $min -MaxVersion $max) -and ([version]$_) -gt ([version]$max) })
    if ($sameMajorNewer.Count -gt 0) {
        Write-RunLog -Log $log -Level ATTN -Message ('Runtime .NET plus récent que la plage de {0} déjà présent ({1}) : l''outil risque d''échouer' -f $ToolLabel, ($sameMajorNewer -join ', '))
    }
    $inRange = @($installed | Where-Object { Test-VersionInRange -Version $_ -MinVersion $min -MaxVersion $max })
    if ($inRange.Count -gt 0) {
        Write-RunLog -Log $log -Message ('Runtime .NET Desktop {0} déjà présent pour {1}' -f ($inRange -join ', '), $ToolLabel)
        return
    }

    Assert-WingetAvailable -FamilyName $Context.Config.Winget.FamilyName -OfflineBundle $Context.Paths.WingetBundle -Log $log
    $result = Install-WingetPackage -Id $Requirement.WingetId -Source 'winget' -Version $max -SourceRepair (Get-WingetSourceRepair -Context $Context) -Log $log
    $after = @(Get-DotNetDesktopRuntimeVersion | Where-Object { Test-VersionInRange -Version $_ -MinVersion $min -MaxVersion $max })
    if ($after.Count -eq 0) {
        throw ('runtime .NET installé hors de la plage requise ({0} à {1}) pour {2}' -f $min, $(if ($max) { $max } else { '…' }), $ToolLabel)
    }
    [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
