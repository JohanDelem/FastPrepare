<#
    Source winget inutilisable (0x8A15000F) : réparation automatique unique par
    « winget source update », message lisible sinon (itération 10, DEC20).
    winget est simulé : aucune commande réelle n'est lancée.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
    $m = @{ ModuleName = 'FastPrepare.Infrastructure' }
    $sourceDataMissing = -1978335217
    $noPackageFound = -1978335212
    $showOutput = "Trouvé Microsoft Visual Studio Code [Microsoft.VisualStudioCode]`r`nVersion : 1.143.1"

    function Get-Calls { @($script:calls) }
}

Describe 'Source winget inutilisable' {
    BeforeEach {
        $script:calls = New-Object System.Collections.Generic.List[string]
        Mock @m Get-Command { [pscustomobject]@{ Source = 'C:\winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
        $log = New-RunLog -Folder (Join-Path $TestDrive 'logs') -FallbackFolder (Join-Path $TestDrive 'repli') -HostName 'PC-TEST' -Stamp ([guid]::NewGuid().ToString('N'))
    }

    It 'réparée par « winget source update » : nouvel essai réussi, journalisé' {
        $script:showCount = 0
        Mock @m Invoke-ExternalProcess {
            $script:calls.Add($ArgumentList)
            if ($ArgumentList -like 'source update*') { return [pscustomobject]@{ ExitCode = 0; Output = '' } }
            $script:showCount++
            if ($script:showCount -eq 1) { return [pscustomobject]@{ ExitCode = $sourceDataMissing; Output = '' } }
            [pscustomobject]@{ ExitCode = 0; Output = $showOutput }
        }
        $info = Get-WingetPackageInfo -Id 'Microsoft.VisualStudioCode' -Source 'winget' -Log $log
        $info.Version | Should -Be '1.143.1'
        $calls = Get-Calls
        $calls.Count | Should -Be 3
        $calls[0] | Should -BeLike 'show --id Microsoft.VisualStudioCode*'
        $calls[1] | Should -BeLike 'source update*'
        $calls[2] | Should -BeLike 'show --id Microsoft.VisualStudioCode*'
        $text = (Receive-RunLogEntry -Log $log).Line -join "`n"
        $text | Should -Match 'Source winget inutilisable pour le compte'
        $text | Should -Match 'Source winget réparée'
    }

    It 'toujours inutilisable : message lisible avec le compte et les commandes, jamais de reset automatique' {
        Mock @m Invoke-ExternalProcess {
            $script:calls.Add($ArgumentList)
            if ($ArgumentList -like 'source update*') { return [pscustomobject]@{ ExitCode = 0; Output = '' } }
            [pscustomobject]@{ ExitCode = $sourceDataMissing; Output = '' }
        }
        $message = try { [void](Get-WingetPackageInfo -Id 'Microsoft.VisualStudioCode' -Source 'winget' -Log $log); '' } catch { $_.Exception.Message }
        $message | Should -Match ([regex]::Escape("compte « $([Environment]::UserName) »"))
        $message | Should -Match '0x8A15000F'
        $message | Should -Match 'winget source reset --force, puis winget source update'
        $message | Should -Not -Match '-1978335217'
        @(Get-Calls | Where-Object { $_ -like 'source reset*' }).Count | Should -Be 0
        @(Get-Calls | Where-Object { $_ -like 'source update*' }).Count | Should -Be 1
    }

    It '« winget source update » en échec : le nouvel essai a quand même lieu' {
        $script:showCount = 0
        Mock @m Invoke-ExternalProcess {
            $script:calls.Add($ArgumentList)
            if ($ArgumentList -like 'source update*') { throw '« winget.exe » : code de sortie 1' }
            $script:showCount++
            if ($script:showCount -eq 1) { return [pscustomobject]@{ ExitCode = $sourceDataMissing; Output = '' } }
            [pscustomobject]@{ ExitCode = 0; Output = $showOutput }
        }
        (Get-WingetPackageInfo -Id 'Microsoft.VisualStudioCode' -Source 'winget' -Log $log).Version | Should -Be '1.143.1'
    }

    It 'source saine : un seul appel, aucune mise à jour' {
        Mock @m Invoke-ExternalProcess { $script:calls.Add($ArgumentList); [pscustomobject]@{ ExitCode = 0; Output = $showOutput } }
        [void](Get-WingetPackageInfo -Id 'Microsoft.VisualStudioCode' -Source 'winget')
        (Get-Calls).Count | Should -Be 1
    }

    It 'installation réelle : même réparation, puis winget install relancé' {
        $script:installCount = 0
        Mock @m Invoke-ExternalProcess {
            $script:calls.Add($ArgumentList)
            if ($ArgumentList -like 'source update*') { return [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
            $script:installCount++
            if ($script:installCount -eq 1) { return [pscustomobject]@{ ExitCode = $sourceDataMissing; RebootRequired = $false } }
            [pscustomobject]@{ ExitCode = 0; RebootRequired = $false }
        }
        $result = Install-WingetPackage -Id '7zip.7zip' -Source 'winget' -Log $log
        $result.AlreadyInstalled | Should -BeFalse
        @(Get-Calls | Where-Object { $_ -like 'install --id 7zip.7zip*' }).Count | Should -Be 2
    }

    It 'le code de source inutilisable est accepté par le lanceur pour être traité, pas renvoyé tel quel' {
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; Output = $showOutput } }
        [void](Get-WingetPackageInfo -Id 'Microsoft.VisualStudioCode' -Source 'winget')
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $SuccessExitCode -contains $sourceDataMissing -and $SuccessExitCode -contains $noPackageFound }
    }
}

Describe 'Seconde réparation : paquet de données de la source (DEC21)' {
    BeforeEach {
        $script:calls = New-Object System.Collections.Generic.List[string]
        Mock @m Get-Command { [pscustomobject]@{ Source = 'C:\winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
        Mock @m Save-RemoteFile { Set-Content -LiteralPath $Destination -Value 'paquet'; $Destination }
        Mock @m Assert-TrustedExecutable { }
        Mock @m Add-AppxPackage { $script:installed = $true }
        $script:installed = $false
        $repair = [pscustomobject]@{ PackageUrl = 'https://cdn.exemple.test/cache/source.msix'; ExpectedSigner = 'CN=Microsoft Corporation'; Folder = (Join-Path $TestDrive 'winget-source') }
        $log = New-RunLog -Folder (Join-Path $TestDrive 'logs') -FallbackFolder (Join-Path $TestDrive 'repli') -HostName 'PC-TEST' -Stamp ([guid]::NewGuid().ToString('N'))
        # winget : source inutilisable tant que le paquet n'est pas installé ; « source update » sans effet.
        Mock @m Invoke-ExternalProcess {
            $script:calls.Add($ArgumentList)
            if ($ArgumentList -like 'source update*') { return [pscustomobject]@{ ExitCode = 0; Output = '' } }
            if ($script:installed) { return [pscustomobject]@{ ExitCode = 0; Output = $showOutput } }
            [pscustomobject]@{ ExitCode = $sourceDataMissing; Output = '' }
        }
    }

    It 'mise à jour sans effet : paquet téléchargé, signature exigée, installé, supprimé, puis nouvel essai réussi' {
        (Get-WingetPackageInfo -Id 'Microsoft.VisualStudioCode' -Source 'winget' -SourceRepair $repair -Log $log).Version | Should -Be '1.143.1'
        Should -Invoke @m Save-RemoteFile -Times 1 -ParameterFilter { $Url -eq 'https://cdn.exemple.test/cache/source.msix' -and $Destination -like '*\winget-source\source.msix' }
        Should -Invoke @m Assert-TrustedExecutable -Times 1 -ParameterFilter { $ExpectedSigner -eq 'CN=Microsoft Corporation' }
        Should -Invoke @m Add-AppxPackage -Times 1
        Join-Path $repair.Folder 'source.msix' | Should -Not -Exist
        $text = (Receive-RunLogEntry -Log $log).Line -join "`n"
        $text | Should -Match 'Installation du paquet de données de la source winget'
        $text | Should -Match 'Source winget réparée par l''installation de son paquet de données'
        @(Get-Calls | Where-Object { $_ -like 'source reset*' }).Count | Should -Be 0
    }

    It 'signature refusée : rien n''est installé, fichier supprimé, message lisible' {
        Mock @m Assert-TrustedExecutable { throw 'source.msix est signé par « CN=Inconnu », et non par « CN=Microsoft Corporation »' }
        $message = try { [void](Get-WingetPackageInfo -Id 'Microsoft.VisualStudioCode' -Source 'winget' -SourceRepair $repair -Log $log); '' } catch { $_.Exception.Message }
        Should -Invoke @m Add-AppxPackage -Times 0
        Join-Path $repair.Folder 'source.msix' | Should -Not -Exist
        $message | Should -Match 'CN=Inconnu'
        $message | Should -Match 'winget source reset --force'
    }

    It 'éditeur attendu absent : installation refusée' {
        $repair.ExpectedSigner = ''
        { Get-WingetPackageInfo -Id 'Microsoft.VisualStudioCode' -Source 'winget' -SourceRepair $repair -Log $log } | Should -Throw '*éditeur attendu*'
        Should -Invoke @m Save-RemoteFile -Times 0
    }

    It 'sans paramètres de réparation : seconde tentative sautée, et le message le dit' {
        { Get-WingetPackageInfo -Id 'Microsoft.VisualStudioCode' -Source 'winget' -Log $log } | Should -Throw '*non tentée*SourcePackage*'
        Should -Invoke @m Save-RemoteFile -Times 0
    }

    It 'installation réelle et vérification au démarrage : même réparation' {
        $script:installed = $false
        [void](Install-WingetPackage -Id '7zip.7zip' -Source 'winget' -SourceRepair $repair -Log $log)
        Should -Invoke @m Add-AppxPackage -Times 1
        $script:installed = $false
        (Test-WingetSource -SourceRepair $repair -Log $log).Ready | Should -BeTrue
    }
}

Describe 'Test-WingetSource' {
    BeforeEach { Mock @m Get-Command { [pscustomobject]@{ Source = 'C:\winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' } }

    It 'recherche sans résultat : source prête, sans rien télécharger' {
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = $noPackageFound; Output = 'Aucun package ne correspond' } }
        (Test-WingetSource).Ready | Should -BeTrue
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $ArgumentList -like 'search --query fastprepare-sonde-source --source winget*' }
    }

    It 'source irréparable : pas prête, motif lisible' {
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = $sourceDataMissing; Output = '' } }
        $result = Test-WingetSource -Source 'winget'
        $result.Ready | Should -BeFalse
        $result.Error | Should -Match 'winget source reset --force'
    }

    It 'winget absent : pas prête' {
        Mock @m Get-Command { throw 'introuvable' } -ParameterFilter { $Name -eq 'winget.exe' }
        (Test-WingetSource).Ready | Should -BeFalse
    }
}
