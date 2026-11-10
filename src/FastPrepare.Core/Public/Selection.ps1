<#
    Schéma de ce que le technicien a coché : contrat entre l'interface et le moteur.
    Chaque section d'interface écrit sa propre partie ; le moteur ne lit que cet objet,
    jamais les contrôles WPF. Fonction pure.
#>

function New-Selection {
    <# Sélection vide (rien n'est coché). #>
    [CmdletBinding()]
    param()

    $selection = [pscustomobject]@{
        PSTypeName     = 'FastPrepare.Selection'
        HostName       = [pscustomobject]@{ Enabled = $false; Name = '' }
        Software       = [pscustomobject]@{ Items = @() }
        MicrosoftApps  = [pscustomobject]@{
            OfficeClickToRun = $false
            OfficeMsi        = $false
            OutlookClassic   = $false
            OutlookNew       = $false
            OneNote          = $false
            Teams            = $false
            OneDrive         = $false
            OneDriveFolder   = $false
        }
        LocalAccounts  = [pscustomobject]@{ Items = @() }
        VendorUtility  = [pscustomobject]@{ Key = $null }
        Office         = [pscustomobject]@{ EditionKey = $null; WithoutTeams = $false; IncludedApps = @() }
        Updates        = [pscustomobject]@{ WindowsUpdate = $false; VendorUtility = $false }
        ExtraSoftware  = [pscustomobject]@{ Ids = @() }
        SystemSettings = [pscustomobject]@{ Ipv6Adapters = @(); Power = $false }
    }
    return $selection
}
