@{
    # Analyse statique (tools\Invoke-Lint.ps1). Cible : Windows PowerShell 5.1.
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Le mode Simulation de l'outil remplace -WhatIf : les fonctions Set-*/New-* n'implémentent pas ShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions',
        # Les fonctions du contrat des sections reçoivent toutes ($Section, $Context…) même si elles n'en utilisent qu'une partie.
        'PSReviewUnusedParameter'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
    }
}
