<#
    Étape 8 — Logiciels cochés du catalogue software.json (section 8), installés par winget ou
    depuis un lien direct (itération 9). L'entrée du catalogue est recopiée dans l'action :
    l'exécution ne dépend pas d'une modification ultérieure du catalogue.
#>

Register-Step -Id 'install-software' -Section 8 -Title 'Installation de logiciels' -Plan {
    param($Selection, $Snapshot, $Context)
    $selected = @($Selection.ExtraSoftware.Ids)
    foreach ($software in @($Context.SoftwareCatalog)) {
        if ($selected -notcontains $software.Id) { continue }
        New-StepAction -Label ('{0} : {1}' -f $software.Label, (Format-SoftwareInstallCommand -Entry $software)) -Parameters @{
            Kind = 'InstallSoftware'; Software = $software
        }
    }
} -Invoke {
    param($Action, $Context)
    $software = $Action.Parameters.Software
    $install = $software.Install
    $log = $Context.Log
    switch ([string]$install.Type) {
        'winget' {
            Assert-WingetAvailable -FamilyName $Context.Config.Winget.FamilyName -OfflineBundle $Context.Paths.WingetBundle -Log $log
            $result = Install-WingetPackage -Id $install.Id -Source $install.Source -Override ([string]$install.Override) -Log $log
            if ($result.AlreadyInstalled) { Write-RunLog -Log $log -Message ('{0} : déjà installé' -f $software.Label) }
            return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
        }
        'download' {
            $folder = Join-Path (Join-Path $Context.Paths.Cache 'software') $software.Id
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
