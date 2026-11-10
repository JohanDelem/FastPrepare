<#
    Analyse statique (PSScriptAnalyzer) et contrôle des encodages.
      - *.ps1, *.psm1, *.psd1 : UTF-8 avec BOM (sans BOM, PowerShell 5.1 casse les accents) ;
      - *.cmd : fins de ligne CRLF.
    Échoue (code 1) au premier avertissement.

    Usage : tools\Invoke-Lint.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script console interactif : sortie colorée pour le développeur.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$problems = 0

$files = Get-ChildItem -Path $root -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.cmd' |
    Where-Object { $_.FullName -notmatch '\\(\.git|logs|packages|tools\\out)\\' }

foreach ($file in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $relative = $file.FullName.Substring($root.Length + 1)
    if ($file.Extension -eq '.cmd') {
        if ([regex]::IsMatch([System.Text.Encoding]::ASCII.GetString($bytes), '(?<!\r)\n')) {
            Write-Host "[encodage] $relative : fins de ligne CRLF attendues" -ForegroundColor Red; $problems++
        }
    } elseif (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        Write-Host "[encodage] $relative : UTF-8 avec BOM attendu" -ForegroundColor Red; $problems++
    }
}

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    throw 'PSScriptAnalyzer introuvable : Install-Module PSScriptAnalyzer -Scope CurrentUser'
}
$settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
foreach ($path in @((Join-Path $root 'src'), (Join-Path $root 'tools'), (Join-Path $root 'Preparation.ps1'))) {
    $results = Invoke-ScriptAnalyzer -Path $path -Recurse -Settings $settings
    foreach ($r in $results) {
        $relative = $r.ScriptPath.Substring($root.Length + 1)
        Write-Host ('[{0}] {1}:{2} {3}' -f $r.RuleName, $relative, $r.Line, $r.Message) -ForegroundColor Yellow
        $problems++
    }
}

if ($problems -gt 0) {
    Write-Host "$problems problème(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Aucun problème.' -ForegroundColor Green
