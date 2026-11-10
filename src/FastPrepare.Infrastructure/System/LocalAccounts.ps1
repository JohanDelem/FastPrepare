<#
    Comptes locaux et profils associés. Le choix des comptes supprimables appartient à
    FastPrepare.Core (Split-LocalAccount).
#>

function Get-LocalAccount {
    <# Comptes locaux { Name, Sid, ProfilePath } ; repli sur Win32_UserAccount si Get-LocalUser est indisponible. #>
    [CmdletBinding()]
    param()

    $profiles = @{}
    foreach ($p in (Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue)) {
        $profiles[[string]$p.SID] = [string]$p.LocalPath
    }

    $accounts = $null
    try {
        $accounts = @(Get-LocalUser -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Sid = $_.SID.Value } })
    } catch {
        $accounts = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction SilentlyContinue |
                ForEach-Object { [pscustomobject]@{ Name = $_.Name; Sid = $_.SID } })
    }

    foreach ($account in $accounts) {
        [pscustomobject]@{
            PSTypeName  = 'FastPrepare.LocalAccount'
            Name        = [string]$account.Name
            Sid         = [string]$account.Sid
            ProfilePath = $profiles[[string]$account.Sid]
        }
    }
}
