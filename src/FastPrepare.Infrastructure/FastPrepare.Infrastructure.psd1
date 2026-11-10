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
        'Test-Winget',
        'Assert-WingetAvailable',
        'Install-WingetPackage',
        'Get-WingetInstallArgument',
        'Invoke-ExternalProcess',
        'Get-SystemExecutablePath',
        'Save-RemoteFile',
        'Assert-TrustedExecutable',
        'Set-PowerTimeout',
        'Get-PowerTimeoutSetting',
        'Disable-AdapterIpv6',
        'Rename-LocalComputer',
        'Invoke-CmdLine',
        'Get-ProfileLocation',
        'Remove-GuardedFolder',
        'Stop-ProcessByName',
        'Remove-LocalAccountWithProfile',
        'Remove-AppxEverywhere',
        'Initialize-OdtFolder',
        'Invoke-Odt',
        'Get-OneDriveSetupPath',
        'Uninstall-OneDrive',
        'Remove-DefaultProfileOneDriveRun',
        'Get-MsiProductCodeByName',
        'Uninstall-MsiProduct',
        'Invoke-UninstallCommand',
        'Wait-UninstallEntryRemoval'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
