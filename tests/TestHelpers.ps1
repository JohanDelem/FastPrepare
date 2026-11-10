<#
    Aides communes aux tests : chemins du dépôt et import des modules par chemin absolu.
    Usage dans un fichier de test : BeforeAll { . (Join-Path $PSScriptRoot '..\TestHelpers.ps1') ; Import-FastPrepareModule Core }
#>
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-RepoRoot { return $script:RepoRoot }

function Import-FastPrepareModule {
    param([Parameter(Mandatory)][ValidateSet('Core', 'Infrastructure', 'Application', 'UI')][string[]]$Name)
    foreach ($n in $Name) {
        $module = "FastPrepare.$n"
        Import-Module (Join-Path $script:RepoRoot "src\$module\$module.psd1") -Force -Global
    }
}

function Get-TestConfig {
    <# Copie modifiable de config.json (chaque test part d'une configuration valide). #>
    return (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
}
