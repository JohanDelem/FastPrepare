@{
    RootModule        = 'FastPrepare.Infrastructure.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '694a607d-aa0a-4356-9f4e-44b05fa5fb90'
    Author            = 'FastPrepare'
    Description       = 'Adaptateurs Windows : configuration, journal, privilèges, lecture du poste.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Read-AppConfig',
        'Assert-AppConfig',
        'New-RunLog',
        'Write-RunLog',
        'Receive-RunLogEntry',
        'Test-Administrator',
        'Assert-Administrator',
        'Get-CurrentUserSid',
        'Start-BackgroundWork',
        'Test-BackgroundWorkCompleted',
        'Receive-BackgroundWork',
        'Stop-BackgroundWork',
        'Get-MachineIdentity',
        'Get-UninstallEntry',
        'Get-ExecutableProbe',
        'Get-LocalAccount',
        'Get-PhysicalAdapter',
        'New-ConnectivityProbe',
        'Start-ConnectivityCheck',
        'Read-ConnectivityResult',
        'Close-ConnectivityProbe',
        'Get-OneDriveFolderInfo',
        'Test-Winget'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
