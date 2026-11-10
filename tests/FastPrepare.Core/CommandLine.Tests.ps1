BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
}

Describe 'Split-CommandLine' {
    It '<Line>' -ForEach @(
        @{ Line = '"C:\Program Files\X\unins000.exe" /VERYSILENT'; File = 'C:\Program Files\X\unins000.exe'; ExpectedArguments = '/VERYSILENT' }
        @{ Line = '  "C:\A\u.exe"'; File = 'C:\A\u.exe'; ExpectedArguments = '' }
        @{ Line = 'C:\F\setup.exe /remove /quiet'; File = 'C:\F\setup.exe'; ExpectedArguments = '/remove /quiet' }
        @{ Line = 'C:\Program Files\App\uninstall.exe /S'; File = 'C:\Program Files\App\uninstall.exe'; ExpectedArguments = '/S' }
        @{ Line = 'msiexec.exe /x {GUID} /qn'; File = 'msiexec.exe'; ExpectedArguments = '/x {GUID} /qn' }
        @{ Line = 'ducmd'; File = 'ducmd'; ExpectedArguments = '' }
    ) {
        $result = Split-CommandLine -CommandLine $Line
        $result.FilePath | Should -Be $File
        $result.Arguments | Should -Be $ExpectedArguments
    }

    It 'refuse <Line> (<Why>)' -ForEach @(
        @{ Line = ''; Why = 'vide' }
        @{ Line = '"C:\A\u.exe /S'; Why = 'guillemet non fermé' }
        @{ Line = 'rundll32 shell32,Control_RunDLL'; Why = 'pas d''exécutable reconnaissable' }
    ) {
        { Split-CommandLine -CommandLine $Line } | Should -Throw
    }
}

Describe 'Expand-ConfigPath' {
    BeforeAll { $variables = @{ ProgramFiles = 'C:\Program Files'; OdtFolder = 'C:\ODT' } }

    It 'remplace les variables connues, sans tenir compte de la casse' {
        Expand-ConfigPath -Path '%ProgramFiles%\Dell\dcu-cli.exe' -Variables $variables | Should -Be 'C:\Program Files\Dell\dcu-cli.exe'
        Expand-ConfigPath -Path '%odtfolder%\setup.exe' -Variables $variables | Should -Be 'C:\ODT\setup.exe'
    }
    It 'laisse un chemin sans variable inchangé' {
        Expand-ConfigPath -Path 'ThinInstaller.exe' -Variables $variables | Should -Be 'ThinInstaller.exe'
    }
    It 'signale une variable inconnue (faute de frappe dans config.json)' {
        { Expand-ConfigPath -Path '%ProgramFile%\x.exe' -Variables $variables } | Should -Throw '*%ProgramFile%*'
    }
}
