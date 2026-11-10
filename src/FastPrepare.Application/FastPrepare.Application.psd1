@{
    RootModule        = 'FastPrepare.Application.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '3a45e8aa-be4c-4ea8-ac9f-a37029f88096'
    Author            = 'FastPrepare'
    Description       = 'Cas d''usage : contexte d''exécution, relevé du poste, simulation.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-AppContext',
        'Get-MachineSnapshot',
        'Export-MachineInventory',
        'Invoke-SelectionSimulation'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
