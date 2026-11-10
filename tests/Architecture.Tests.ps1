<#
    Règles d'architecture vérifiées sur les sources (docs/architecture_plan.md §4.1, §6, §7).
    Elles échouent dès qu'une responsabilité sort de sa couche.
#>
BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $src = Join-Path $root 'src'
    function Get-SourceFile([string]$Folder, [string[]]$Filter = @('*.ps1', '*.psm1')) {
        Get-ChildItem -Path $Folder -Recurse -File -Include $Filter | ForEach-Object {
            @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Length + 1) }
        }
    }
    $allCode = @(Get-SourceFile $src) + @(@{ Path = (Join-Path $root 'Preparation.ps1'); Name = 'Preparation.ps1' })
    $nonUi = @(Get-SourceFile (Join-Path $src 'FastPrepare.Core')) + @(Get-SourceFile (Join-Path $src 'FastPrepare.Infrastructure')) + @(Get-SourceFile (Join-Path $src 'FastPrepare.Application'))
    $notInfrastructure = @(Get-SourceFile (Join-Path $src 'FastPrepare.Core')) + @(Get-SourceFile (Join-Path $src 'FastPrepare.Application')) + @(Get-SourceFile (Join-Path $src 'FastPrepare.UI'))
    $corePublic = @(Get-SourceFile (Join-Path $src 'FastPrepare.Core\Public'))
    $bomFiles = @(Get-ChildItem -Path $root -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' |
            Where-Object { $_.FullName -notmatch '\\(logs|packages|\.git)\\' } |
            ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Length + 1) } })
}

BeforeAll {
    function Get-CodeText([string]$Path) {
        # Contenu sans les commentaires de bloc ni de ligne : seules les instructions comptent.
        $text = [System.IO.File]::ReadAllText($Path)
        $text = [regex]::Replace($text, '<#[\s\S]*?#>', '')
        return (($text -split "`r?`n") | ForEach-Object { $_ -replace '(^|\s)#.*$', '' }) -join "`n"
    }

    function Get-InvokedCommand([string]$Path) {
        # Noms des commandes réellement appelées (arbre syntaxique) : le texte des messages ne compte pas.
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        return @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
    }
}

Describe 'Couches' {
    It '<Name> : aucun type WPF hors de FastPrepare.UI' -ForEach $nonUi {
        Get-CodeText $Path | Should -Not -Match 'System\.Windows\.(Controls|Media|Markup|Threading|Documents|Application|MessageBox)'
    }

    It '<Name> : aucun accès système direct hors de FastPrepare.Infrastructure' -ForEach $notInfrastructure {
        $forbidden = @('Get-CimInstance', 'Get-WmiObject', 'Start-Process', 'Get-NetAdapter', 'Get-NetAdapterBinding', 'Disable-NetAdapterBinding', 'Get-LocalUser', 'Remove-LocalUser', 'New-LocalUser', 'Add-LocalGroupMember', 'Get-AppxPackage', 'Add-AppxPackage', 'Remove-AppxPackage', 'Rename-Computer', 'Start-BitsTransfer', 'Get-AuthenticodeSignature', 'Remove-CimInstance', 'Get-AppxProvisionedPackage', 'Remove-AppxProvisionedPackage', 'Stop-Process', 'Remove-ItemProperty')
        @(Get-InvokedCommand $Path | Where-Object { $forbidden -contains $_ }) | Should -BeNullOrEmpty
        Get-CodeText $Path | Should -Not -Match "['`"](HKLM|HKCU):"

    }

    It '<Name> : FastPrepare.Core reste pur (ni fichier, ni registre, ni environnement, ni réseau)' -ForEach $corePublic {
        $forbidden = @('Get-Item', 'Get-ItemProperty', 'Get-ChildItem', 'Get-Content', 'Set-Content', 'Add-Content', 'Out-File', 'Remove-Item', 'Test-Path', 'Invoke-WebRequest', 'Get-Date', 'Write-RunLog')
        @(Get-InvokedCommand $Path | Where-Object { $forbidden -contains $_ }) | Should -BeNullOrEmpty
        Get-CodeText $Path | Should -Not -Match '\$env:|System\.Net|\[System\.IO\.File\]'
    }
}

Describe 'Processus externes' {
    It '<Name> : processus lancés uniquement par Process.ps1' -ForEach ($allCode | Where-Object { $_.Name -notlike '*\System\Process.ps1' }) {
        Get-CodeText $Path | Should -Not -Match '\[System\.Diagnostics\.Process\]|System\.Diagnostics\.ProcessStartInfo'
        @(Get-InvokedCommand $Path | Where-Object { @('Start-Process', 'Invoke-Item') -contains $_ }) | Should -BeNullOrEmpty
    }
}

Describe 'Fils d''exécution' {
    It '<Name> : runspaces créés uniquement par BackgroundRunner.ps1' -ForEach ($allCode | Where-Object { $_.Name -notlike '*\BackgroundRunner.ps1' }) {
        $text = Get-CodeText $Path
        $text | Should -Not -Match 'RunspaceFactory|\[(System\.Management\.Automation\.)?PowerShell\]::Create'
        @(Get-InvokedCommand $Path | Where-Object { @('Start-Job', 'Start-ThreadJob') -contains $_ }) | Should -BeNullOrEmpty
    }
}

Describe 'Sécurité' {
    It '<Name> : jamais d''Invoke-Expression' -ForEach $allCode {
        @(Get-InvokedCommand $Path | Where-Object { @('Invoke-Expression', 'iex') -contains $_ }) | Should -BeNullOrEmpty
    }

    It '<Name> : jamais de redémarrage automatique' -ForEach $allCode {
        @(Get-InvokedCommand $Path | Where-Object { $_ -eq 'Restart-Computer' }) | Should -BeNullOrEmpty
        Get-CodeText $Path | Should -Not -Match '\s-Restart\b'
    }

    It '<Name> : un mot de passe n''est jamais converti en texte (DEC15)' -ForEach ($allCode | Where-Object { $_.Name -notlike '*\Public\LocalAccountCreation.ps1' }) {
        # Pwd*.Password : texte en clair d'une PasswordBox (seule SecurePassword est permise).
        Get-CodeText $Path | Should -Not -Match 'SecureStringTo(BSTR|GlobalAlloc|CoTaskMem)|PtrToString|NetworkCredential|\bPwd\w*\.Password\b'
        @(Get-InvokedCommand $Path | Where-Object { @('ConvertFrom-SecureString') -contains $_ }) | Should -BeNullOrEmpty
    }

    It '<Name> : la comparaison des mots de passe libère toujours sa copie non managée' -ForEach ($allCode | Where-Object { $_.Name -like '*\Public\LocalAccountCreation.ps1' }) {
        $text = Get-CodeText $Path
        ([regex]::Matches($text, 'SecureStringToBSTR')).Count | Should -Be ([regex]::Matches($text, 'ZeroFreeBSTR')).Count
    }

    It 'config.json n''est jamais réécrit par l''outil (DEC17)' {
        $path = Join-Path $PSScriptRoot '..\src\FastPrepare.Infrastructure\Config\AppConfig.ps1'
        @(Get-InvokedCommand $path | Where-Object { @('Set-Content', 'Out-File', 'Add-Content', 'Move-Item', 'Copy-Item') -contains $_ }) | Should -BeNullOrEmpty
        Get-CodeText $path | Should -Not -Match 'WriteAll(Text|Bytes)|::Replace\('
    }

    It '<Name> : le catalogue des logiciels n''est écrit que par Application/SoftwareCatalog.ps1' -ForEach ($allCode | Where-Object { $_.Name -notlike '*\FastPrepare.Application\SoftwareCatalog.ps1' -and $_.Name -notlike '*\Config\SoftwareCatalog.ps1' }) {
        @(Get-InvokedCommand $Path | Where-Object { $_ -eq 'Save-SoftwareCatalog' }) | Should -BeNullOrEmpty
    }

    It '<Name> : aucun lien dans le code (les liens vivent dans config.json)' -ForEach $allCode {
        Get-CodeText $Path | Should -Not -Match 'https?://(?!schemas\.microsoft\.com)[\w-]+\.'
    }
}

Describe 'Encodage' {
    It '<Name> : UTF-8 avec BOM (sinon PowerShell 5.1 casse les accents)' -ForEach $bomFiles {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
    }

    It 'Lancer.cmd : fins de ligne CRLF' {
        $text = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\Lancer.cmd'))
        ([regex]::Matches($text, '(?<!\r)\n')).Count | Should -Be 0
    }
}

Describe 'Manifestes' {
    It '<_> : chaque fonction exportée existe' -ForEach @('FastPrepare.Core', 'FastPrepare.Infrastructure', 'FastPrepare.Application', 'FastPrepare.UI') {
        $manifest = Join-Path $PSScriptRoot "..\src\$_\$_.psd1"
        $declared = (Import-PowerShellDataFile -Path $manifest).FunctionsToExport
        $module = Import-Module $manifest -Force -PassThru
        $missing = @($declared | Where-Object { -not $module.ExportedFunctions.ContainsKey($_) })
        $missing | Should -BeNullOrEmpty
    }
}
