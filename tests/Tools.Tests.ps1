<#
    tools\Build-Usb.ps1 : seul le nécessaire part sur la clé, les journaux existants sont conservés.
#>
BeforeAll {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $build = Join-Path $root 'tools\Build-Usb.ps1'
}

Describe 'Build-Usb' {
    It 'copie le strict nécessaire et conserve les journaux déjà présents sur la clé' {
        $destination = Join-Path $TestDrive 'CLE'
        New-Item -ItemType Directory -Path (Join-Path $destination 'logs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'logs\Journal_ancien.log') -Value 'à conserver'
        New-Item -ItemType Directory -Path (Join-Path $destination 'src\obsolete') -Force | Out-Null

        & $build -Destination $destination -SkipChecks 6>$null

        foreach ($item in 'Lancer.cmd', 'Preparation.ps1', 'config.json', 'software.json', 'VERSION.txt', 'src\FastPrepare.Core\FastPrepare.Core.psd1', 'src\FastPrepare.UI\Xaml\MainWindow.xaml', 'logos') {
            Join-Path $destination $item | Should -Exist
        }
        foreach ($item in 'tests', 'docs', 'tools', '.git', 'README.md', 'src\obsolete') {
            Join-Path $destination $item | Should -Not -Exist
        }
        Join-Path $destination 'logs\Journal_ancien.log' | Should -Exist
        Get-Content -LiteralPath (Join-Path $destination 'VERSION.txt') -Raw | Should -Match 'config.json : SHA256 [0-9A-F]{64}'
    }

    It 'conserve le catalogue des logiciels de la clé, sauf avec -ReplaceSoftwareCatalog' {
        $destination = Join-Path $TestDrive 'CLE2'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'software.json') -Value '{ "CatalogVersion": 1, "Software": [] }'
        & $build -Destination $destination -SkipChecks 6>$null
        Get-Content -LiteralPath (Join-Path $destination 'software.json') -Raw | Should -Match '"Software": \[\]'
        & $build -Destination $destination -SkipChecks -ReplaceSoftwareCatalog 6>$null
        Get-Content -LiteralPath (Join-Path $destination 'software.json') -Raw | Should -Match 'adobe-reader'
    }

    It 'refuse une destination à l''intérieur du dépôt' {
        { & $build -Destination (Join-Path $root 'out-cle') -SkipChecks 6>$null } | Should -Throw '*intérieur du dépôt*'
    }
}
