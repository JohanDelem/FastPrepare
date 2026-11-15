<#
    tools\Build-Release.ps1 : seul le nécessaire part dans le livrable, les journaux et le catalogue
    déjà présents sont conservés, l'archive ne contient aucun journal.
#>
BeforeAll {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $build = Join-Path $root 'tools\Build-Release.ps1'
    $version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') | Select-Object -First 1).Trim()
    $name = "FastPrepare-$version"
}

Describe 'Build-Release' {
    It 'fichier VERSION : majeur.itération.correctif' {
        $version | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'copie le strict nécessaire et conserve les journaux déjà présents' {
        $destination = Join-Path $TestDrive 'livraison1'
        $target = Join-Path $destination $name
        New-Item -ItemType Directory -Path (Join-Path $target 'logs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'logs\Journal_ancien.log') -Value 'à conserver'
        New-Item -ItemType Directory -Path (Join-Path $target 'src\obsolete') -Force | Out-Null

        & $build -Destination $destination -SkipChecks 6>$null

        foreach ($item in 'Lancer.cmd', 'Preparation.ps1', 'VERSION', 'config.json', 'software.json', 'BUILD.txt', 'src\FastPrepare.Core\FastPrepare.Core.psd1', 'src\FastPrepare.UI\Xaml\MainWindow.xaml') {
            Join-Path $target $item | Should -Exist
        }
        foreach ($item in 'tests', 'docs', 'tools', '.git', 'README.md', 'src\obsolete') {
            Join-Path $target $item | Should -Not -Exist
        }
        Join-Path $target 'logs\Journal_ancien.log' | Should -Exist
        $buildInfo = Get-Content -LiteralPath (Join-Path $target 'BUILD.txt') -Raw
        $buildInfo | Should -Match 'config.json : SHA256 [0-9A-F]{64}'
        $buildInfo | Should -Match ([regex]::Escape("Version     : $version"))
    }

    It 'conserve le catalogue des logiciels déjà présent, sauf avec -ReplaceSoftwareCatalog' {
        $destination = Join-Path $TestDrive 'livraison2'
        $target = Join-Path $destination $name
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'software.json') -Value '{ "CatalogVersion": 1, "Software": [] }'
        & $build -Destination $destination -SkipChecks 6>$null
        Get-Content -LiteralPath (Join-Path $target 'software.json') -Raw | Should -Match '"Software": \[\]'
        & $build -Destination $destination -SkipChecks -ReplaceSoftwareCatalog 6>$null
        Get-Content -LiteralPath (Join-Path $target 'software.json') -Raw | Should -Match 'adobe-reader'
    }

    It '-Zip : archive versionnée, sans aucun journal' {
        $destination = Join-Path $TestDrive 'livraison3'
        $target = Join-Path $destination $name
        New-Item -ItemType Directory -Path (Join-Path $target 'logs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'logs\Journal_ancien.log') -Value 'N/S et MAC'

        & $build -Destination $destination -SkipChecks -Zip 6>$null

        $archive = Join-Path $destination "$name.zip"
        $archive | Should -Exist
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
        try { $entries = @($zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' }) } finally { $zip.Dispose() }
        $entries | Should -Contain "$name/Lancer.cmd"
        $entries | Should -Contain "$name/src/FastPrepare.Core/FastPrepare.Core.psd1"
        @($entries | Where-Object { $_ -match '\.log$' }) | Should -BeNullOrEmpty
    }

    It 'refuse une destination à l''intérieur du dépôt' {
        { & $build -Destination (Join-Path $root 'out-livraison') -SkipChecks 6>$null } | Should -Throw '*intérieur du dépôt*'
    }
}
