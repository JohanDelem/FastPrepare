<#
    Adaptateurs de suppression : jamais exécutés pour de vrai sur le poste. Les commandes Windows
    sont remplacées par des simulacres ; seule la suppression de dossier est réelle, et toujours
    dans le dossier de test de Pester ($TestDrive).
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
    $m = @{ ModuleName = 'FastPrepare.Infrastructure' }
    $sid = 'S-1-5-21-1111111111-2222222222-3333333333-1002'
}

Describe 'Remove-GuardedFolder (suppressions réelles, dans $TestDrive)' {
    BeforeEach {
        $root = Join-Path $TestDrive ('Users-' + [guid]::NewGuid().ToString('N'))
        $current = Join-Path $root 'technicien'
        $oneDrive = Join-Path $current 'OneDrive'
        New-Item -ItemType Directory -Path (Join-Path $oneDrive 'Documents') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $oneDrive 'Documents\a.txt') -Value 'x'
        New-Item -ItemType Directory -Path (Join-Path $root 'Default\OneDrive') -Force | Out-Null
    }

    It 'supprime le dossier OneDrive du profil connecté' {
        (Remove-GuardedFolder -Path $oneDrive -ProfilesRoot $root -CurrentProfile $current -AllowInsideProfile).Changed | Should -BeTrue
        $oneDrive | Should -Not -Exist
        $current | Should -Exist
    }
    It 'dossier déjà absent : sans effet' {
        (Remove-GuardedFolder -Path (Join-Path $current 'Absent') -ProfilesRoot $root -CurrentProfile $current -AllowInsideProfile).Changed | Should -BeFalse
    }
    It 'refuse <Why>, sans rien supprimer' -ForEach @(
        @{ Why = 'le profil connecté entier'; Target = { $current } }
        @{ Why = 'le dossier des profils'; Target = { $root } }
        @{ Why = 'un dossier du profil Default'; Target = { Join-Path $root 'Default\OneDrive' } }
        @{ Why = 'une évasion par ..'; Target = { Join-Path $oneDrive '..\..\..' } }
    ) {
        $path = & $Target
        { Remove-GuardedFolder -Path $path -ProfilesRoot $root -CurrentProfile $current -AllowInsideProfile } | Should -Throw '*garde de chemin*'
        $oneDrive | Should -Exist
        (Join-Path $root 'Default\OneDrive') | Should -Exist
    }
}

Describe 'Remove-LocalAccountWithProfile' {
    It 'supprime le profil puis le compte' {
        Mock @m Get-CimInstance { [pscustomobject]@{ Loaded = $false; LocalPath = 'C:\Users\ancien' } }
        Mock @m Remove-CimInstance { } -RemoveParameterType InputObject
        Mock @m Test-Path { $false }
        Mock @m Get-LocalUser { [pscustomobject]@{ Name = 'ancien' } }
        Mock @m Remove-LocalUser { }
        $result = Remove-LocalAccountWithProfile -Sid $sid
        $result.ProfileRemoved | Should -BeTrue
        $result.AccountRemoved | Should -BeTrue
        Should -Invoke @m Remove-LocalUser -Times 1 -ParameterFilter { [string]$SID -eq $sid }
    }
    It 'profil chargé (session ouverte) : refus, rien supprimé' {
        Mock @m Get-CimInstance { [pscustomobject]@{ Loaded = $true; LocalPath = 'C:\Users\ancien' } }
        Mock @m Remove-CimInstance { } -RemoveParameterType InputObject
        Mock @m Remove-LocalUser { }
        { Remove-LocalAccountWithProfile -Sid $sid } | Should -Throw '*chargé*'
        Should -Invoke @m Remove-CimInstance -Times 0
        Should -Invoke @m Remove-LocalUser -Times 0
    }
    It 'compte et profil déjà absents : succès sans action' {
        Mock @m Get-CimInstance { $null }
        Mock @m Get-LocalUser { throw 'introuvable' }
        Mock @m Remove-LocalUser { }
        $result = Remove-LocalAccountWithProfile -Sid $sid
        $result.AccountRemoved | Should -BeFalse
        Should -Invoke @m Remove-LocalUser -Times 0
    }
    It 'refuse un SID qui n''est pas celui d''un compte local (<Sid>)' -ForEach @(@{ Sid = 'S-1-5-18' }, @{ Sid = 'n''importe quoi' }) {
        { Remove-LocalAccountWithProfile -Sid $Sid } | Should -Throw '*SID*'
    }
}

Describe 'Remove-AppxEverywhere' {
    It 'retire le paquet pour tous les utilisateurs et le paquet provisionné' {
        Mock @m Get-AppxPackage { [pscustomobject]@{ PackageFullName = 'Microsoft.OutlookForWindows_1.0_x64__8wekyb3d8bbwe' } }
        Mock @m Remove-AppxPackage { }
        Mock @m Get-AppxProvisionedPackage { @([pscustomobject]@{ DisplayName = 'Microsoft.OutlookForWindows'; PackageName = 'Microsoft.OutlookForWindows_1.0_neutral' }, [pscustomobject]@{ DisplayName = 'Autre'; PackageName = 'Autre_1' }) }
        Mock @m Remove-AppxProvisionedPackage { }
        $result = Remove-AppxEverywhere -Name 'Microsoft.OutlookForWindows'
        @($result.Provisioned) | Should -Be @('Microsoft.OutlookForWindows_1.0_neutral')
        Should -Invoke @m Remove-AppxPackage -Times 1 -ParameterFilter { $AllUsers }
        Should -Invoke @m Remove-AppxProvisionedPackage -Times 1 -ParameterFilter { $PackageName -eq 'Microsoft.OutlookForWindows_1.0_neutral' }
    }
    It 'rien d''installé : succès sans retrait' {
        Mock @m Get-AppxPackage { }
        Mock @m Get-AppxProvisionedPackage { }
        Mock @m Remove-AppxPackage { }
        $result = Remove-AppxEverywhere -Name 'MSTeams'
        @($result.Installed).Count | Should -Be 0
        Should -Invoke @m Remove-AppxPackage -Times 0
    }
    It 'refuse un nom de paquet avec des jokers ou des espaces' {
        { Remove-AppxEverywhere -Name '*' } | Should -Throw
        { Remove-AppxEverywhere -Name 'a b' } | Should -Throw
    }
}

Describe 'ODT' {
    It 'setup.exe présent : pas de téléchargement, signature vérifiée' {
        $folder = Join-Path $TestDrive 'ODT1'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'setup.exe') -Value 'x'
        Mock @m Save-RemoteFile { }
        Mock @m Assert-TrustedExecutable { }
        Initialize-OdtFolder -Folder $folder -SetupUrl 'https://exemple.test/setup.exe' | Should -Be (Join-Path $folder 'setup.exe')
        Should -Invoke @m Save-RemoteFile -Times 0
        Should -Invoke @m Assert-TrustedExecutable -Times 1 -ParameterFilter { $ExpectedSigner -eq 'Microsoft' }
    }
    It 'setup.exe absent : téléchargé depuis le lien de la configuration' {
        $folder = Join-Path $TestDrive 'ODT2'
        Mock @m Save-RemoteFile { }
        Mock @m Assert-TrustedExecutable { }
        [void](Initialize-OdtFolder -Folder $folder -SetupUrl 'https://exemple.test/setup.exe')
        Should -Invoke @m Save-RemoteFile -Times 1 -ParameterFilter { $Url -eq 'https://exemple.test/setup.exe' }
    }
    It 'Invoke-Odt : XML écrit à côté de setup.exe, puis setup.exe /configure' {
        $folder = Join-Path $TestDrive 'ODT3'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
        $result = Invoke-Odt -SetupPath (Join-Path $folder 'setup.exe') -Xml '<Configuration />' -Name 'suppression'
        $result.ConfigurationPath | Should -Exist
        Get-Content -LiteralPath $result.ConfigurationPath -Raw | Should -Be '<Configuration />'
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $ArgumentList -eq ('/configure "{0}"' -f $result.ConfigurationPath) }
    }
}

Describe 'OneDrive' {
    It 'chaque installateur trouvé est lancé avec /uninstall, /allusers pour l''installation pour tous' {
        Mock @m Get-OneDriveSetupPath { @([pscustomobject]@{ Path = 'C:\Windows\System32\OneDriveSetup.exe'; AllUsers = $false }, [pscustomobject]@{ Path = 'C:\Program Files\Microsoft OneDrive\24.1\OneDriveSetup.exe'; AllUsers = $true }) }
        Mock @m Stop-ProcessByName { 0 }
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
        (Uninstall-OneDrive).Changed | Should -BeTrue
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -like '*System32*' -and $ArgumentList -eq '/uninstall' }
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -like '*Program Files*' -and $ArgumentList -eq '/uninstall /allusers' }
    }
    It 'aucun installateur : déjà désinstallé' {
        Mock @m Get-OneDriveSetupPath { }
        Mock @m Invoke-ExternalProcess { }
        (Uninstall-OneDrive).Changed | Should -BeFalse
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }
    It 'profil par défaut : la ruche est déchargée même si la suppression échoue' {
        $default = Join-Path $TestDrive 'Default'
        New-Item -ItemType Directory -Path $default | Out-Null
        Set-Content -LiteralPath (Join-Path $default 'NTUSER.DAT') -Value 'x'
        Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
        Mock @m Test-Path { $true } -ParameterFilter { $LiteralPath -like 'Registry::*' }
        Mock @m Get-ItemProperty { [pscustomobject]@{ OneDriveSetup = 'x' } }
        Mock @m Remove-ItemProperty { throw 'accès refusé' }
        { Remove-DefaultProfileOneDriveRun -DefaultProfilePath $default } | Should -Throw '*accès refusé*'
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $ArgumentList -like 'load HKU\FastPrepareDefault*' }
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $ArgumentList -eq 'unload HKU\FastPrepareDefault' }
    }
}

Describe 'Désinstallation de logiciels' {
    BeforeEach { Mock @m Invoke-ExternalProcess { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } } }

    It 'MSI : msiexec de System32, produit déjà absent (1605) accepté' {
        [void](Invoke-UninstallCommand -Command 'msiexec.exe /x {11111111-2222-3333-4444-555555555555} /qn /norestart')
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -like '*\System32\msiexec.exe' -and $ArgumentList -eq '/x {11111111-2222-3333-4444-555555555555} /qn /norestart' -and $SuccessExitCode -contains 1605 }
    }
    It 'exécutable entre guillemets : chemin et arguments séparés' {
        [void](Invoke-UninstallCommand -Command '"C:\Program Files\App\unins000.exe" /VERYSILENT')
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $FilePath -eq 'C:\Program Files\App\unins000.exe' -and $ArgumentList -eq '/VERYSILENT' -and -not $Interactive }
    }
    It 'assistant : fenêtre affichée' {
        [void](Invoke-UninstallCommand -Command 'C:\F\setup.exe /remove' -Interactive)
        Should -Invoke @m Invoke-ExternalProcess -Times 1 -ParameterFilter { $Interactive }
    }
    It 'commande non analysable : repli cmd.exe /c, tracé' {
        Mock @m Invoke-CmdLine { [pscustomobject]@{ ExitCode = 0; RebootRequired = $false } }
        [void](Invoke-UninstallCommand -Command 'rundll32 shell32,Control_RunDLL x')
        Should -Invoke @m Invoke-CmdLine -Times 1
        Should -Invoke @m Invoke-ExternalProcess -Times 0
    }
    It 'Uninstall-MsiProduct refuse un code produit mal formé' {
        { Uninstall-MsiProduct -ProductCode 'abc' } | Should -Throw
    }
    It 'Wait-UninstallEntryRemoval : vrai dès que l''entrée a disparu, faux après le délai' {
        Mock @m Get-UninstallEntry { }
        Wait-UninstallEntryRemoval -DisplayName 'App' -TimeoutSeconds 1 -PollSeconds 1 | Should -BeTrue
        Mock @m Get-UninstallEntry { [pscustomobject]@{ DisplayName = 'App'; DisplayVersion = '1.0' } }
        Wait-UninstallEntryRemoval -DisplayName 'App' -DisplayVersion '1.0' -TimeoutSeconds 1 -PollSeconds 1 | Should -BeFalse
        Wait-UninstallEntryRemoval -DisplayName 'App' -DisplayVersion '2.0' -TimeoutSeconds 1 -PollSeconds 1 | Should -BeTrue
    }
}
