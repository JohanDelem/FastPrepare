<#
    Ordre d'exécution du cahier des charges, à un seul endroit.
    « L'ordre est fixé par l'outil, quel que soit l'ordre d'affichage. Seules les actions cochées
    s'exécutent. » Le rapport final (14) n'est pas une étape : c'est la conclusion du moteur.
    Ajouter une étape = l'insérer ici à sa place (Assert-StepCatalog vérifie la cohérence).
#>

function Get-StepOrder {
    <# Identifiants des étapes, dans l'ordre d'exécution (rang 1 à 13). #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @(
        'export-inventory'          # 1.  Relevé et export des N/S et MAC (section 10)
        'remove-local-accounts'     # 2.  Sessions locales et profils (section 4)
        'remove-microsoft-apps'     # 3.  Office, Outlook, OneNote, Teams (section 3)
        'remove-onedrive'           # 4.  OneDrive, puis son dossier (section 3)
        'uninstall-software'        # 5.  Logiciels : silencieux d'abord, assistants en dernier (section 2)
        'install-vendor-utility'    # 6.  Dépendances (.NET) puis utilitaire constructeur (section 5)
        'install-office'            # 7.  Office via ODT (section 6)
        'install-software'          # 8.  Logiciels du catalogue, dont Adobe Acrobat Reader (section 8)
        'disable-ipv6'              # 9.  IPv6 sur les cartes cochées (section 9)
        'set-power-plan'            # 10. Mode d'alimentation (section 9)
        'update-vendor-utility'     # 11. MàJ utilitaire : pilotes, BIOS (section 7)
        'run-windows-update'        # 12. Windows Update (section 7)
        'rename-computer'           # 13. Nom d'hôte, pris en compte au redémarrage (section 1)
    )
}
