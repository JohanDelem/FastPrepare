BeforeDiscovery {
    $stepFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..\..\src\FastPrepare.Application\Steps') -Filter '*.step.ps1' |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
}

Describe 'Catalogue des étapes' {
    It 'ordre d''exécution (DEC27) : 12 étapes, sans doublon' {
        $order = @(Get-StepOrder)
        $order.Count | Should -Be 12
        @($order | Sort-Object -Unique).Count | Should -Be 12
    }

    It 'une seule étape d''installation, avant les réglages et les mises à jour (DEC26)' {
        $order = @(Get-StepOrder)
        @($order | Where-Object { $_ -like 'install*' }) | Should -Be @('install')
        [array]::IndexOf($order, 'install') | Should -Be 5
        [array]::IndexOf($order, 'update-drivers') | Should -BeGreaterThan ([array]::IndexOf($order, 'install'))
        [array]::IndexOf($order, 'create-local-account') | Should -Be 11
    }

    It 'chaque étape de l''ordre est enregistrée, et réciproquement' {
        $catalog = Get-RegisteredStep
        @($catalog.Keys | Sort-Object) | Should -Be @(Get-StepOrder | Sort-Object)
    }

    It '<Name> : enregistre exactement une étape' -ForEach $stepFiles {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Register-Step' }, $false))
        $calls.Count | Should -Be 1
    }

    It 'titre renseigné pour chaque étape (préfixe des avertissements du plan)' {
        foreach ($step in (Get-RegisteredStep).Values) { $step.Title | Should -Not -BeNullOrEmpty }
    }
}
