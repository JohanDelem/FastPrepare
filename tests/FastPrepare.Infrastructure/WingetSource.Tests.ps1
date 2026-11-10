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
