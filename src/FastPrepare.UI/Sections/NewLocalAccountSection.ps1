<#
    Section 11 — Créer une session locale (fonctionnalité ajoutée après le cahier, itération 8).
    Saisie vérifiée par FastPrepare.Core (Get-LocalAccountNameError, Get-LocalAccountPasswordError).
    Le mot de passe n'est jamais lu en clair : seule PasswordBox.SecurePassword est utilisée, et
    chaque copie est libérée dès qu'elle ne sert plus (DEC15).
#>

Register-UiSection -Id 'new-local-account' -Number 11 -Column Left -XamlFile 'Sections\NewLocalAccount.xaml' -Initialize {
    param($Section, $Context)
    $c = $Section.Controls
    $Section.State.DefaultHint = "20 caractères max · mot de passe saisi deux fois, jamais écrit dans le journal · profil créé à la première ouverture de session"
    $Section.State.ExistingNames = @()
    $Section.State.RemovedNames = @()
    $Section.State.ComputerNames = @()

    # Valeurs par défaut du parc (config.json, bloc facultatif NewLocalAccount).
    $defaults = @{ Administrator = $false; PasswordNeverExpires = $true; MustChangePassword = $false }
    if ($Context.Config.PSObject.Properties['NewLocalAccount']) {
        foreach ($key in @($defaults.Keys)) {
            if ($Context.Config.NewLocalAccount.PSObject.Properties[$key]) { $defaults[$key] = [bool]$Context.Config.NewLocalAccount.$key }
        }
    }
    $c.ChkNewAdmin.IsChecked = $defaults.Administrator
    $c.ChkNewNeverExpires.IsChecked = $defaults.PasswordNeverExpires
    $c.ChkNewMustChange.IsChecked = $defaults.MustChangePassword -and -not $defaults.PasswordNeverExpires

    # Update-UiState rappelle Refresh, qui met à jour l'affichage de la section.
    $onChange = { Invoke-UiAction -Name 'session à créer' -Action { Update-UiState } }
    $c.ChkNewAccount.Add_Click($onChange)
    $c.ChkNewAdmin.Add_Click($onChange)
    $c.TxtNewName.Add_TextChanged($onChange)
    $c.PwdNew.Add_PasswordChanged($onChange)
    $c.PwdNewConfirm.Add_PasswordChanged($onChange)
    # « N'expire jamais » et « à changer à la première ouverture » s'excluent (Windows ignorerait le second).
    $c.ChkNewNeverExpires.Add_Click({
            Invoke-UiAction -Name 'session à créer' -Action {
                $controls = (Get-UiSection -Id 'new-local-account').Controls
                if ($controls.ChkNewNeverExpires.IsChecked) { $controls.ChkNewMustChange.IsChecked = $false }
                Update-UiState
            }
        })
    $c.ChkNewMustChange.Add_Click({
            Invoke-UiAction -Name 'session à créer' -Action {
                $controls = (Get-UiSection -Id 'new-local-account').Controls
                if ($controls.ChkNewMustChange.IsChecked) { $controls.ChkNewNeverExpires.IsChecked = $false }
                Update-UiState
            }
        })
    $c.TxtNewHint.Text = $Section.State.DefaultHint
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $Section.State.ExistingNames = @($Snapshot.LocalAccounts.Names)
    $Section.State.CurrentHostName = [string]$Snapshot.Identity.HostName
    Update-NewLocalAccountView
} -Refresh {
    param($Section, $Selection)
    # Un nom libéré par la section 4 redevient disponible ; le futur nom du poste est interdit.
    $Section.State.RemovedNames = @(@($Selection.LocalAccounts.Items) | ForEach-Object { [string]$_.Name })
    $computers = @($Section.State.CurrentHostName)
    if ($Selection.HostName.Enabled) { $computers += [string]$Selection.HostName.Name }
    $Section.State.ComputerNames = @($computers | Where-Object { $_ })
    Update-NewLocalAccountView
} -GetSelection {
    param($Section, $Selection)
    $c = $Section.Controls
    $account = $Selection.NewLocalAccount
    $account.Enabled = [bool]$c.ChkNewAccount.IsChecked
    if (-not $account.Enabled) { return }
    $account.Name = [string]$c.TxtNewName.Text
    $account.FullName = ([string]$c.TxtNewFullName.Text).Trim()
    $password = $c.PwdNew.SecurePassword    # copie : libérée par Clear-SelectionSecret
    $password.MakeReadOnly()
    $account.Password = $password
    $account.Administrator = [bool]$c.ChkNewAdmin.IsChecked
    $account.PasswordNeverExpires = [bool]$c.ChkNewNeverExpires.IsChecked
    $account.MustChangePassword = [bool]$c.ChkNewMustChange.IsChecked
} -Validate {
    param($Section)
    $problem = Get-NewLocalAccountInputError -Section $Section
    if ($problem) { return "Grisé : session à créer — $problem" }
    return $null
}

function Get-NewLocalAccountInputError {
    <# Motif qui empêche de créer la session saisie, ou $null (case décochée ou saisie correcte). #>
    param($Section)
    $c = $Section.Controls
    if (-not $c.ChkNewAccount.IsChecked) { return $null }

    $existing = @($Section.State.ExistingNames | Where-Object { $Section.State.RemovedNames -notcontains $_ })
    $nameError = Get-LocalAccountNameError -Name ([string]$c.TxtNewName.Text) -ExistingName $existing -ComputerName @($Section.State.ComputerNames)
    if ($nameError) { return $nameError }

    $password = $c.PwdNew.SecurePassword
    $confirmation = $c.PwdNewConfirm.SecurePassword
    try {
        return (Get-LocalAccountPasswordError -Password $password -Confirmation $confirmation)
    } finally {
        $password.Dispose()
        $confirmation.Dispose()
    }
}

function Update-NewLocalAccountView {
    $section = Get-UiSection -Id 'new-local-account'
    $c = $section.Controls
    $enabled = [bool]$c.ChkNewAccount.IsChecked
    $c.PnlNewAccount.IsEnabled = $enabled

    # Rien de saisi : consigne ; sinon le motif du refus, en rouge.
    $password = $c.PwdNew.SecurePassword
    try { $typed = $c.TxtNewName.Text.Length -gt 0 -or $password.Length -gt 0 } finally { $password.Dispose() }
    $problem = if ($enabled -and $typed) { Get-NewLocalAccountInputError -Section $section } else { $null }
    if ($problem) {
        $c.TxtNewHint.Text = 'À corriger : {0}' -f $problem
        $c.TxtNewHint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
    } else {
        $c.TxtNewHint.Text = $section.State.DefaultHint
        $c.TxtNewHint.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    }
}
