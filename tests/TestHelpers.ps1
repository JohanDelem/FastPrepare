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

function New-TestSnapshot {
    <# Relevé de poste fictif (aucune donnée réelle). #>
    param([switch]$InventoryExportFailed)
    $export = if ($InventoryExportFailed) { [pscustomobject]@{ Path = $null; Error = 'clé retirée' } } else { [pscustomobject]@{ Path = 'C:\Cle\logs\Inventaire_SN0000TEST_test.txt'; Error = $null } }
    return [pscustomobject]@{
        PSTypeName          = 'FastPrepare.MachineSnapshot'
        Identity            = [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'Latitude'; Serial = 'SN0000TEST'; OsLabel = 'Windows 11'; HostName = 'PC-TEST' }
        WingetAvailable     = $true
        Software            = @()
        LocalAccounts       = [pscustomobject]@{
            Removable = @([pscustomobject]@{ Name = 'ancien'; Sid = 'S-1-5-21-1-2-3-1002'; ProfilePath = 'C:\Users\ancien' })
            Excluded  = @('Administrateur', 'technicien (connecté)')
            Names     = @('Administrateur', 'Invité', 'technicien', 'ancien')
        }
        Adapters            = @(
            [pscustomobject]@{ Name = 'Ethernet'; Description = 'Carte filaire'; Mac = '00-11-22-33-44-55'; Ipv6Enabled = $true }
            [pscustomobject]@{ Name = 'Wi-Fi'; Description = 'Carte sans fil'; Mac = '66-77-88-99-AA-BB'; Ipv6Enabled = $false }
        )
        OneDrive            = [pscustomobject]@{ Path = 'C:\Users\technicien\OneDrive'; Exists = $true; FileCount = 42 }
        Profiles            = [pscustomobject]@{ Root = 'C:\Users'; Current = 'C:\Users\technicien'; Default = 'C:\Users\Default' }
        SuggestedUtilityKey = 'dell'
        InventoryText       = 'N/S SN0000TEST'
        InventoryExport     = $export
    }
}

function New-TestContext {
    <# Contexte de test : configuration du dépôt, journal dans un dossier de test. #>
    param([Parameter(Mandatory)][string]$Folder, [string]$Mode = 'Simulation', $Config)
    if (-not $Config) { $Config = Get-TestConfig }
    $log = New-RunLog -Folder (Join-Path $Folder 'logs') -FallbackFolder (Join-Path $Folder 'repli') -HostName 'PC-TEST' -Stamp ([guid]::NewGuid().ToString('N'))
    $cache = Join-Path $Folder 'cache'
    $paths = [pscustomobject]@{
        Logs         = $log.Folder
        OdtFolder    = 'C:\ODT'
        WingetBundle = 'C:\Cle\packages\winget.msixbundle'
        Cache        = $cache
        Variables    = @{ 'ProgramFiles' = 'C:\Program Files'; 'ProgramFiles(x86)' = 'C:\Program Files (x86)'; 'ProgramData' = 'C:\ProgramData'; 'OdtFolder' = 'C:\ODT'; 'CacheFolder' = $cache }
    }
    $paths | Add-Member -NotePropertyName SoftwareCatalog -NotePropertyValue (Join-Path $Folder 'software.json')
    # Catalogue du dépôt (software.json), comme au démarrage de l'outil.
    $catalog = (Read-SoftwareCatalog -Path (Join-Path $script:RepoRoot 'software.json')).Entries
    return [pscustomobject]@{ Config = $Config; Mode = $Mode; Stamp = 'test'; Log = $log; Paths = $paths; ModulePaths = @(); SoftwareCatalog = @($catalog) }
}
