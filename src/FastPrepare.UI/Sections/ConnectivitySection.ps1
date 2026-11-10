<#
    Section 0 — Connexion internet (pastille de l'en-tête).
    Test périodique, non bloquant ; tant que la connexion n'est pas validée, Lancer reste grisé.
    Seuls les changements d'état sont journalisés.
#>

Register-UiSection -Id 'connectivity' -Number 0 -Column Header -Initialize {
    param($Section, $Context)
    $settings = $Context.Config.Connectivity
    $Section.State.Settings = $settings
    $Section.State.Ok = $false
    $Section.State.Known = $false
    $Section.State.NextCheck = Get-Date
    $Section.State.Probe = New-ConnectivityProbe -Url $settings.TestUrl -Expected $settings.Expected -TimeoutSeconds $settings.TimeoutSeconds

    Register-UiTickHandler -Name 'connectivity' -ScriptBlock { Update-ConnectivityState -Section (Get-UiSection -Id 'connectivity') }
} -Validate {
    param($Section)
    if (-not $Section.State.Ok) { return 'Grisé : connexion internet non validée' }
    return $null
} -Dispose {
    param($Section)
    if ($Section.State.Probe) { Close-ConnectivityProbe -Probe $Section.State.Probe }
}

function Update-ConnectivityState {
    <# Appelé à chaque battement de la pompe : lance un test à l'échéance, lit son résultat quand il arrive. #>
    param($Section)
    $state = $Section.State
    $probe = $state.Probe

    if ($probe.Task) {
        $result = Read-ConnectivityResult -Probe $probe
        if ($result -eq 'Pending') { return }
        $state.NextCheck = (Get-Date).AddSeconds([int]$state.Settings.IntervalSeconds)
        Set-ConnectivityState -Section $Section -Ok ($result -eq 'Ok')
        return
    }

    if ((Get-Date) -ge $state.NextCheck) {
        try {
            Start-ConnectivityCheck -Probe $probe
        } catch {
            $state.NextCheck = (Get-Date).AddSeconds([int]$state.Settings.RetrySeconds)
            Set-ConnectivityState -Section $Section -Ok $false
        }
    }
}

function Set-ConnectivityState {
    param($Section, [bool]$Ok)
    $state = $Section.State
    $changed = ($Ok -ne $state.Ok) -or (-not $state.Known)
    $state.Known = $true
    $state.Ok = $Ok
    if (-not $changed) { return }

    if ($Ok) { Write-RunLog -Log $script:Context.Log -Level OK -Message 'Connexion internet validée' }
    else { Write-RunLog -Log $script:Context.Log -Level ERREUR -Message 'Pas de connexion internet' }

    $controls = $Section.Controls
    $prefix = if ($Ok) { 'NetOk' } else { 'NetKo' }
    $controls.BdNet.Background = Get-ThemeResource -Key "${prefix}BackgroundBrush"
    $controls.NetDot.Fill = Get-ThemeResource -Key "${prefix}DotBrush"
    $controls.TxtNet.Foreground = Get-ThemeResource -Key "${prefix}TextBrush"
    $controls.TxtNet.Text = if ($Ok) { 'Connecté à internet' } else { 'Pas de connexion internet' }
    Update-LaunchState
}
