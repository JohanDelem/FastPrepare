<#
    Étape 6 — Dépendances (.NET) puis utilitaire constructeur (section 5).
    La version de l'outil proposée par winget n'est connue qu'à l'exécution : la dépendance .NET
    est choisie à ce moment par Select-DotNetRequirement (FastPrepare.Core).
#>

Register-Step -Id 'install-vendor-utility' -Section 5 -Title 'Installation de l''utilitaire constructeur' -Plan {
    param($Selection, $Snapshot, $Context)
    $key = $Selection.VendorUtility.Key
    if (-not $key) { return }
    $utility = $Context.Config.Utilities.$key

    if ($utility.PSObject.Properties['DotNet'] -and @($utility.DotNet).Count -gt 0) {
        New-StepAction -Label ('Dépendance : runtime .NET Desktop adapté à la version de {0} proposée par winget' -f $utility.Tool) -Parameters @{
            Kind = 'DotNetDependency'; UtilityKey = $key
        }
    }

    $index = 0
    foreach ($item in @($utility.Install)) {
        if ($item.Type -eq 'winget') {
            $label = 'Utilitaire : winget install --id {0} --source {1} --silent' -f $item.Id, $item.Source
        } else {
            $url = if ($item.Url) { $item.Url } else { 'lien à renseigner dans config.json' }
            $label = 'Utilitaire : téléchargement direct de {0} ({1})' -f $item.FileName, $url
            if (-not $item.Url) { New-PlanWarning -Message ("{0} : lien de téléchargement de {1} vide dans config.json, l'installation réelle échouera." -f $utility.Tool, $item.FileName) }
        }
        New-StepAction -Label $label -Parameters @{ Kind = 'UtilityInstall'; UtilityKey = $key; ItemIndex = $index }
        $index++
    }
} -Invoke {
    param($Action, $Context)
    $log = $Context.Log
    $key = $Action.Parameters.UtilityKey
    $utility = $Context.Config.Utilities.$key

    switch ($Action.Parameters.Kind) {
        'DotNetDependency' {
            $resolution = Resolve-UtilityDotNetRequirement -UtilityKey $key -Context $Context
            $requirement = $resolution.Requirement
            if (-not $requirement) {
                Write-RunLog -Log $log -Level ATTN -Message ('{0} {1} : aucune entrée DotNet de config.json ne s''applique, aucun runtime installé' -f $utility.Tool, $resolution.ToolVersion)
                return
            }
            if (-not $resolution.IsExactMatch) {
                Write-RunLog -Log $log -Level ATTN -Message ('{0} {1} absent de config.json (DotNet) : règle de la version {2} appliquée' -f $utility.Tool, $resolution.ToolVersion, $requirement.DcuVersion)
            }
            Install-DotNetRequirement -Requirement $requirement -ToolLabel ('{0} {1}' -f $utility.Tool, $resolution.ToolVersion) -Context $Context
        }
        'UtilityInstall' {
            $item = @($utility.Install)[$Action.Parameters.ItemIndex]
            if ($item.Type -eq 'winget') {
                Assert-WingetAvailable -FamilyName $Context.Config.Winget.FamilyName -OfflineBundle $Context.Paths.WingetBundle -Log $log
                $result = Install-WingetPackage -Id $item.Id -Source $item.Source -Log $log
                if ($result.AlreadyInstalled) { Write-RunLog -Log $log -Message ('{0} : déjà installé' -f $item.Id) }
                return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
            }
            if (-not $item.Url) { throw ("lien de téléchargement de {0} vide dans config.json" -f $item.FileName) }
            $path = Get-PrefetchedItem -UtilityKey $key -Item $item -Context $Context
            if ($path) { Write-RunLog -Log $log -Message "Fichier préchargé utilisé : $path" }
            else { $path = Save-RemoteFile -Url $item.Url -Destination (Get-PrefetchCachePath -UtilityKey $key -Item $item -Context $Context) -Sha256 ([string]$item.Sha256) -Log $log }
            # Vérifié au moment de lancer, qu'il vienne du cache ou d'être téléchargé.
            Assert-TrustedExecutable -Path $path -ExpectedSigner ([string]$item.ExpectedSigner)
            $result = Invoke-ExternalProcess -FilePath $path -ArgumentList ([string]$item.Arguments) -TimeoutMinutes 30 -Log $log
            [pscustomobject]@{ RebootRequired = $result.RebootRequired }
        }
        default { throw "action inconnue : $($Action.Parameters.Kind)" }
    }
}

function Install-DotNetRequirement {
    <#
        Garantit un runtime .NET Desktop dans la plage requise. Déjà présent → rien. Sinon installation
        par winget, à la version maximale de la plage si elle est bornée (un runtime trop récent fait
        échouer DCU 5.7.0), puis vérification. Un runtime plus récent déjà présent est signalé.
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
    $result = Install-WingetPackage -Id $Requirement.WingetId -Source 'winget' -Version $max -Log $log
    $after = @(Get-DotNetDesktopRuntimeVersion | Where-Object { Test-VersionInRange -Version $_ -MinVersion $min -MaxVersion $max })
    if ($after.Count -eq 0) {
        throw ('runtime .NET installé hors de la plage requise ({0} à {1}) pour {2}' -f $min, $(if ($max) { $max } else { '…' }), $ToolLabel)
    }
    [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
