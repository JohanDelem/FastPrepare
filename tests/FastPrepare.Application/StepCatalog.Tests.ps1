BeforeDiscovery {
    $stepFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..\..\src\FastPrepare.Application\Steps') -Filter '*.step.ps1' |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure, Application
}

Describe 'Catalogue des étapes' {
    It 'ordre du cahier et fonctionnalités ajoutées : 14 étapes, sans doublon' {
        $order = @(Get-StepOrder)
        $order.Count | Should -Be 14
        @($order | Sort-Object -Unique).Count | Should -Be 14
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

    It 'section de l''interface renseignée pour chaque étape (1 à 11)' {
        foreach ($step in (Get-RegisteredStep).Values) {
            $step.Section | Should -BeGreaterOrEqual 1
            $step.Section | Should -BeLessOrEqual 11
        }
    }
}
