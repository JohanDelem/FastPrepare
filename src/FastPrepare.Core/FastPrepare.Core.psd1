@{
    RootModule        = 'FastPrepare.Core.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '03746fcd-ad31-42e4-90d4-ce0ea5df98cc'
    Author            = 'FastPrepare'
    Description       = 'Règles pures de préparation de poste : aucun accès au système ni à WPF.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-HostNameError',
        'Test-HostName',
        'Get-UninstallMsiProductCode',
        'Get-UninstallExecutable',
        'Get-UninstallProbeTarget',
        'Resolve-UninstallStrategy',
        'Get-UninstallOrder',
        'Get-ProtectedAccountReason',
        'Test-ProtectedAccount',
        'Split-LocalAccount',
        'Get-OfficeEdition',
        'Test-OfficeEditionHasNoTeamsVariant',
        'Get-OfficeProductId',
        'Get-ExcludedOfficeApp',
        'New-OdtInstallXml',
        'Resolve-UtilityKey',
        'Format-InventoryText',
        'Format-InventoryExport',
        'ConvertTo-SafeFileName',
        'New-Selection'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
