<#
    OneDrive : état du dossier, désinstallation, démarrage automatique pour les nouveaux profils.
#>

function Get-OneDriveFolderInfo {
    <# Dossier OneDrive d'un profil : { Path, Exists, FileCount }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfilePath)

    $path = Join-Path $ProfilePath 'OneDrive'
    $exists = Test-Path -LiteralPath $path -PathType Container
    $count = 0
    if ($exists) {
        $count = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    }
    return [pscustomobject]@{ Path = $path; Exists = $exists; FileCount = $count }
}

function Get-OneDriveSetupPath {
    <#
        Installateurs OneDrive présents : { Path, AllUsers }.
        Système (System32, SysWOW64), installation pour tous (Program Files) et par utilisateur (LocalAppData).
    #>
    [CmdletBinding()]
    param()
    $windows = [Environment]::GetFolderPath('Windows')
    foreach ($path in @((Join-Path $windows 'System32\OneDriveSetup.exe'), (Join-Path $windows 'SysWOW64\OneDriveSetup.exe'))) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { [pscustomobject]@{ Path = $path; AllUsers = $false } }
    }
    $machine = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Microsoft OneDrive'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $machine '*\OneDriveSetup.exe') -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{ Path = $file.FullName; AllUsers = $true }
    }
    $user = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Microsoft\OneDrive'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $user '*\OneDriveSetup.exe') -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{ Path = $file.FullName; AllUsers = $false }
    }
}

function Uninstall-OneDrive {
    <#
        Arrête OneDrive puis lance chaque installateur trouvé avec /uninstall (/allusers pour
        l'installation pour tous). Aucun installateur = déjà désinstallé. Renvoie { Changed }.
    #>
    [CmdletBinding()]
    param($Log)
    $setups = @(Get-OneDriveSetupPath)
    if ($setups.Count -eq 0) { return [pscustomobject]@{ Changed = $false } }
    [void](Stop-ProcessByName -Name 'OneDrive')
    foreach ($setup in $setups) {
        $arguments = if ($setup.AllUsers) { '/uninstall /allusers' } else { '/uninstall' }
        [void](Invoke-ExternalProcess -FilePath $setup.Path -ArgumentList $arguments -TimeoutMinutes 15 -Log $Log)
    }
    return [pscustomobject]@{ Changed = $true }
}

function Remove-DefaultProfileOneDriveRun {
    <#
        Retire la valeur Run\OneDriveSetup du profil par défaut (sinon OneDrive se réinstalle à
        chaque nouveau profil). La ruche est toujours déchargée, même en cas d'erreur.
        Renvoie { Changed }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DefaultProfilePath,
        $Log
    )
    $hive = Join-Path $DefaultProfilePath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $hive -PathType Leaf)) { throw "Ruche du profil par défaut introuvable : $hive" }

    $reg = Get-SystemExecutablePath -Name 'reg.exe'
    $mount = 'HKU\FastPrepareDefault'
    [void](Invoke-ExternalProcess -FilePath $reg -ArgumentList ('load {0} "{1}"' -f $mount, $hive) -TimeoutMinutes 2 -Log $Log)
    $changed = $false
    try {
        $runKey = 'Registry::HKEY_USERS\FastPrepareDefault\Software\Microsoft\Windows\CurrentVersion\Run'
        if ((Test-Path -LiteralPath $runKey) -and $null -ne (Get-ItemProperty -LiteralPath $runKey -Name 'OneDriveSetup' -ErrorAction SilentlyContinue)) {
            Remove-ItemProperty -LiteralPath $runKey -Name 'OneDriveSetup' -ErrorAction Stop
            $changed = $true
        }
    } finally {
        # Libère les poignées PowerShell sur la ruche avant de la décharger.
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        [void](Invoke-ExternalProcess -FilePath $reg -ArgumentList "unload $mount" -TimeoutMinutes 2 -Log $Log)
    }
    return [pscustomobject]@{ Changed = $changed }
}
