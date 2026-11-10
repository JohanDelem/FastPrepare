BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
    $users = 'C:\Users'
    $current = 'C:\Users\technicien'
}

Describe 'Test-SafeProfilePath (suppression d''un profil, section 4)' {
    It 'accepte le profil d''un autre compte : <Path>' -ForEach @(
        @{ Path = 'C:\Users\ancien' }, @{ Path = 'c:\users\Ancien\' }
    ) {
        Test-SafeProfilePath -Path $Path -ProfilesRoot $users -CurrentProfile $current | Should -BeTrue
    }

    It 'refuse <Path> (<Why>)' -ForEach @(
        @{ Path = 'C:\Users'; Why = 'dossier des profils lui-même' }
        @{ Path = 'C:\Users\'; Why = 'dossier des profils, séparateur final' }
        @{ Path = 'C:\Users\Default'; Why = 'profil par défaut' }
        @{ Path = 'C:\Users\Public'; Why = 'dossier public' }
        @{ Path = 'C:\Users\technicien'; Why = 'profil connecté' }
        @{ Path = 'C:\Users\TECHNICIEN'; Why = 'profil connecté, autre casse' }
        @{ Path = 'C:\Users\ancien\..\..\Windows'; Why = 'évasion par ..' }
        @{ Path = 'C:\Windows'; Why = 'hors du dossier des profils' }
        @{ Path = 'C:\Users\ancien\Documents'; Why = 'sous-dossier, pas un profil entier' }
        @{ Path = 'ancien'; Why = 'chemin relatif' }
        @{ Path = 'C:\Usersbis\x'; Why = 'préfixe trompeur' }
    ) {
        Test-SafeProfilePath -Path $Path -ProfilesRoot $users -CurrentProfile $current | Should -BeFalse
    }
}

Describe 'Test-SafeProfilePath -AllowInsideProfile (dossier OneDrive, section 3)' {
    It 'accepte un sous-dossier du profil connecté' {
        Test-SafeProfilePath -Path 'C:\Users\technicien\OneDrive' -ProfilesRoot $users -CurrentProfile $current -AllowInsideProfile | Should -BeTrue
    }
    It 'refuse le profil entier' {
        Test-SafeProfilePath -Path 'C:\Users\technicien' -ProfilesRoot $users -CurrentProfile $current -AllowInsideProfile | Should -BeFalse
    }
    It 'refuse un sous-dossier de Default' {
        Test-SafeProfilePath -Path 'C:\Users\Default\OneDrive' -ProfilesRoot $users -CurrentProfile $current -AllowInsideProfile | Should -BeFalse
    }
}

Describe 'Test-SafeChildPath' {
    It 'accepte un enfant, refuse la racine et l''évasion' {
        Test-SafeChildPath -Path 'C:\ODT\setup.exe' -Root 'C:\ODT' | Should -BeTrue
        Test-SafeChildPath -Path 'C:\ODT' -Root 'C:\ODT' | Should -BeFalse
        Test-SafeChildPath -Path 'C:\ODT\..\Windows' -Root 'C:\ODT' | Should -BeFalse
        Test-SafeChildPath -Path 'C:\ODTx\a' -Root 'C:\ODT' | Should -BeFalse
    }
}
