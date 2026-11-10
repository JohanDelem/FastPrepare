<#
    Téléchargements et vérification des exécutables avant lancement (plan d'architecture §7.1).
    HTTPS uniquement ; BITS (fourni avec Windows, cahier des charges), repli HttpClient ;
    écriture sous un nom temporaire puis renommage : un fichier partiel n'est jamais réutilisé.
#>

function Save-RemoteFile {
    <# Télécharge -Url vers -Destination ; vérifie l'empreinte SHA-256 si fournie. Renvoie le chemin. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [AllowEmptyString()][string]$Sha256,
        $Log
    )

    if ($Url -notmatch '^https://') { throw "Téléchargement refusé (lien https:// attendu) : $Url" }
    $folder = Split-Path -Path $Destination -Parent
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $partial = "$Destination.partiel"
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }

    if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Téléchargement : $Url → $Destination" }
    try {
        Start-BitsTransfer -Source $Url -Destination $partial -ErrorAction Stop
    } catch {
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "BITS indisponible ($($_.Exception.Message)), repli HttpClient" }
        Save-HttpFile -Url $Url -Destination $partial
    }

    if ($Sha256) {
        $actual = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
        if ($actual -ne $Sha256.Trim().ToUpperInvariant()) {
            Remove-Item -LiteralPath $partial -Force
            throw "Empreinte SHA-256 inattendue pour $Url (attendue $Sha256, obtenue $actual) : fichier supprimé."
        }
    }
    Move-Item -LiteralPath $partial -Destination $Destination -Force
    return $Destination
}

function Save-HttpFile {
    param([string]$Url, [string]$Destination)
    $client = New-Object System.Net.Http.HttpClient
    try {
        $client.Timeout = [TimeSpan]::FromMinutes(30)
        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        [void]$response.EnsureSuccessStatusCode()
        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $target = [System.IO.File]::Create($Destination)
        try { $source.CopyTo($target) } finally { $target.Dispose(); $source.Dispose() }
    } finally {
        $client.Dispose()
    }
}

function Assert-TrustedExecutable {
    <#
        Refuse de laisser lancer un exécutable dont la signature Authenticode n'est pas valide, ou
        dont le certificat ne mentionne pas l'éditeur attendu (-ExpectedSigner, ex. « Microsoft »).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$ExpectedSigner
    )
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw ("Signature de {0} non valide ({1}) : exécutable non lancé." -f [System.IO.Path]::GetFileName($Path), $signature.Status)
    }
    $subject = [string]$signature.SignerCertificate.Subject
    if ($ExpectedSigner -and $subject -notmatch [regex]::Escape($ExpectedSigner)) {
        throw ("{0} est signé par « {1} », et non par « {2} » : exécutable non lancé." -f [System.IO.Path]::GetFileName($Path), $subject, $ExpectedSigner)
    }
}
