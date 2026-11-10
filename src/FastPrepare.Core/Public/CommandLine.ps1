<#
    Lignes de commande Windows et chemins de la configuration. Fonctions pures.
    Un processus externe se lance toujours avec un exécutable et des arguments séparés
    (docs/architecture_plan.md §7.1) : ces fonctions font la séparation.
#>

function Split-CommandLine {
    <#
        Découpe une ligne de commande en { FilePath, Arguments } :
          "C:\Program Files\X\u.exe" /S   → C:\Program Files\X\u.exe | /S
          C:\X\setup.exe /remove          → C:\X\setup.exe | /remove
          msiexec.exe                      → msiexec.exe | (vide)
        Erreur explicite si la ligne n'est pas analysable (guillemet non fermé, pas d'exécutable).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$CommandLine)

    $line = $CommandLine.Trim()
    if (-not $line) { throw 'Ligne de commande vide.' }

    if ($line.StartsWith('"')) {
        $end = $line.IndexOf('"', 1)
        if ($end -lt 0) { throw "Ligne de commande non analysable (guillemet non fermé) : $CommandLine" }
        $filePath = $line.Substring(1, $end - 1).Trim()
        $arguments = $line.Substring($end + 1).Trim()
    } elseif ($line -match '(?i)^(.+?\.(exe|cmd|bat|com))(\s+(.*))?$') {
        $filePath = $Matches[1]
        $arguments = if ($Matches[4]) { $Matches[4].Trim() } else { '' }
    } elseif ($line -notmatch '\s') {
        $filePath = $line
        $arguments = ''
    } else {
        throw "Ligne de commande non analysable : $CommandLine"
    }

    if (-not $filePath) { throw "Ligne de commande non analysable (exécutable vide) : $CommandLine" }
    return [pscustomobject]@{ FilePath = $filePath; Arguments = $arguments }
}

function Expand-ConfigPath {
    <#
        Remplace les variables %Nom% d'un chemin de config.json à partir de -Variables
        (table fournie par l'appelant : ProgramFiles, OdtFolder, CacheFolder…).
        Une variable inconnue est une erreur : une faute de frappe dans la configuration est
        signalée au lieu de produire un chemin faux.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][hashtable]$Variables
    )

    $lookup = @{}
    foreach ($key in $Variables.Keys) { $lookup[([string]$key).ToUpperInvariant()] = [string]$Variables[$key] }

    $unknown = New-Object System.Collections.Generic.List[string]
    $result = [regex]::Replace($Path, '%([^%\\/]+)%', {
            param($match)
            $name = $match.Groups[1].Value.ToUpperInvariant()
            if ($lookup.ContainsKey($name)) { return $lookup[$name] }
            $unknown.Add($match.Value)
            return $match.Value
        })
    if ($unknown.Count -gt 0) {
        throw ("Variable inconnue dans le chemin '{0}' : {1}" -f $Path, ($unknown -join ', '))
    }
    return $result
}
