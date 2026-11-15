<#
    Ordre d'exécution, à un seul endroit. L'ordre est fixé par l'outil, quel que soit l'ordre
    d'affichage ; seules les actions cochées s'exécutent. Le rapport final n'est pas une étape :
    c'est la conclusion du moteur.
    Ajouter une étape = l'insérer ici à sa place (Assert-StepCatalog vérifie la cohérence).
    Numérotation propre à l'outil depuis l'itération 13 (DEC27) : le plan d'architecture en est
    la référence, plus le cahier des charges d'origine.
#>

function Get-StepOrder {
    <# Identifiants des étapes, dans l'ordre d'exécution (rang 1 à 12). #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @(
        'export-inventory'          # 1.  Relevé et export des N/S et MAC
        'remove-local-accounts'     # 2.  Sessions locales et profils
        'remove-microsoft-apps'     # 3.  Office, Outlook, OneNote, Teams
        'remove-onedrive'           # 4.  OneDrive, puis son dossier
        'uninstall-software'        # 5.  Logiciels : silencieux d'abord, assistants en dernier
        'install'                   # 6.  Installations : entrées du catalogue, puis Office (DEC26)
        'disable-ipv6'              # 7.  IPv6 sur les cartes cochées
        'set-power-plan'            # 8.  Mode d'alimentation
        'update-drivers'            # 9.  Pilotes et BIOS par l'outil du constructeur
        'run-windows-update'        # 10. Windows Update
        'rename-computer'           # 11. Nom d'hôte, pris en compte au redémarrage
        'create-local-account'      # 12. Session locale à créer
    )
}
