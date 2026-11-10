<#
    Applications du Store (Appx/MSIX) : retrait pour tous les utilisateurs et du paquet
    provisionné (sinon l'application revient pour chaque nouveau profil).
#>

function Remove-AppxEverywhere {
    <#
        Retire le paquet -Name pour tous les utilisateurs, puis le paquet provisionné du même nom.
        Rien à retirer = succès. Renvoie { Installed, Provisioned } : les noms complets retirés.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        $Log
    )
    if ($Name -notmatch '^[A-Za-z0-9.\-]+$') { throw "Nom de paquet Appx invalide : '$Name'." }

    $installed = @(Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue)
    foreach ($package in $installed) {
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Remove-AppxPackage -AllUsers $($package.PackageFullName)" }
        Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
    }

    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $Name })
    foreach ($package in $provisioned) {
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Remove-AppxProvisionedPackage $($package.PackageName)" }
        [void](Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop)
    }

    return [pscustomobject]@{
        Installed   = @($installed | ForEach-Object { $_.PackageFullName })
        Provisioned = @($provisioned | ForEach-Object { $_.PackageName })
    }
}
