<#
    Étape 14 — Création d'une session locale (section 11, fonctionnalité ajoutée après le cahier,
    décisions DEC14 à DEC16 du plan d'architecture).
    Le mot de passe voyage en SecureString dans Parameters, que le moteur ne journalise jamais ;
    le libellé est construit sans lui (Format-LocalAccountSummary ne le reçoit pas).
#>

Register-Step -Id 'create-local-account' -Section 11 -Title 'Création d''une session locale' -Plan {
    param($Selection, $Snapshot, $Context)
    $account = $Selection.NewLocalAccount
    if (-not $account -or -not $account.Enabled) { return }

    $summary = Format-LocalAccountSummary -Name $account.Name -FullName $account.FullName -Administrator:([bool]$account.Administrator) -PasswordNeverExpires:([bool]$account.PasswordNeverExpires) -MustChangePassword:([bool]$account.MustChangePassword)
    $computerNames = @([string]$Snapshot.Identity.HostName)
    if ($Selection.HostName.Enabled) { $computerNames += [string]$Selection.HostName.Name }

    New-StepAction -Label ("Session locale : New-LocalUser {0}" -f $summary) -Parameters @{
        Kind                 = 'NewLocalAccount'
        Name                 = [string]$account.Name
        FullName             = [string]$account.FullName
        Password             = $account.Password
        Administrator        = [bool]$account.Administrator
        PasswordNeverExpires = [bool]$account.PasswordNeverExpires
        MustChangePassword   = [bool]$account.MustChangePassword
        ComputerNames        = $computerNames
    }
} -Invoke {
    param($Action, $Context)
    $p = $Action.Parameters
    # Dernière vérification avec les comptes relus sur le poste (des sessions ont pu être supprimées ou créées entre-temps).
    $existing = @(Get-LocalAccount | ForEach-Object { [string]$_.Name })
    $nameError = Get-LocalAccountNameError -Name $p.Name -ExistingName $existing -ComputerName $p.ComputerNames
    if ($nameError) { throw "nom de session refusé ($nameError)" }
    $passwordError = Get-LocalAccountPasswordError -Password $p.Password
    if ($passwordError) { throw $passwordError }

    $groups = Get-LocalAccountGroupSid -Administrator:([bool]$p.Administrator)
    $result = New-LocalAccount -Name $p.Name -FullName $p.FullName -Password $p.Password -GroupSid $groups -PasswordNeverExpires:([bool]$p.PasswordNeverExpires) -MustChangePassword:([bool]$p.MustChangePassword) -Log $Context.Log
    Write-RunLog -Log $Context.Log -Message ("Session '{0}' créée ; son profil sera créé à la première ouverture de session" -f $result.Name)
}
