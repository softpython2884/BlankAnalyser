<#
.SYNOPSIS
    BlankAnalyser - Triage statique cote HOTE. N'EXECUTE JAMAIS LA CIBLE.
.DESCRIPTION
    Analyse un fichier telecharge sans jamais le lancer :
      - empreinte SHA-256 (a coller sur VirusTotal : recherche par hash = 0 octet d'upload)
      - provenance (Mark-of-the-Web)
      - signature Authenticode
      - scan Microsoft Defender a la demande
      - inventaire d'archive SANS extraction, avec reperage des extensions a risque
.EXAMPLE
    .\Triage-Host.ps1 -Target .\quarantine\jeu.zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Target,
    [switch]$NoDefenderScan
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = (Resolve-Path $Target).Path
$item = Get-Item $Target

$RISKY = @('.exe','.dll','.bat','.cmd','.ps1','.psm1','.vbs','.vbe','.js','.jse','.wsf','.wsh',
           '.scr','.msi','.msp','.hta','.lnk','.pif','.com','.cpl','.jar','.reg','.sys','.inf')

$lines = New-Object System.Collections.Generic.List[string]
function Emit($t, $color = 'Gray') { $lines.Add($t) | Out-Null; Write-Host $t -ForegroundColor $color }

Emit "# BlankAnalyser - Triage statique"
Emit ""
Emit "- **Cible**   : $($item.Name)"
Emit "- **Chemin**  : $($item.FullName)"
Emit "- **Taille**  : $([math]::Round($item.Length/1MB,2)) Mo ($($item.Length) octets)"
Emit "- **Modifie** : $($item.LastWriteTime)"
Emit ""

# --- Hash ------------------------------------------------------------------
Write-Host "[..] Calcul SHA-256..." -ForegroundColor Gray
$sha = (Get-FileHash -Path $Target -Algorithm SHA256).Hash
Emit "## Empreinte"
Emit ""
Emit "``````"
Emit "SHA-256 : $sha"
Emit "``````"
Emit ""
Emit "**Recherche VirusTotal par hash (aucun upload, ~0 bande passante) :**"
Emit ""
Emit "  https://www.virustotal.com/gui/file/$sha"
Emit ""
Emit "> Si la page existe : le fichier est deja connu, tu as 70+ moteurs gratuitement."
Emit "> Si elle n'existe pas : personne ne l'a jamais soumis. Pour un jeu indie obscur"
Emit "> c'est normal, mais ca veut dire que l'analyse comportementale est ta seule reponse."
Emit ""

# --- Mark of the Web -------------------------------------------------------
Emit "## Provenance (Mark-of-the-Web)"
Emit ""
$zone = Get-Content -Path $Target -Stream Zone.Identifier -ErrorAction SilentlyContinue
if ($zone) {
    Emit "``````"
    $zone | ForEach-Object { Emit $_ }
    Emit "``````"
} else {
    Emit "_Aucun flux Zone.Identifier : le fichier n'a pas ete marque comme telecharge_"
    Emit "_(archive deja extraite, copie via USB, ou marquage supprime)._"
}
Emit ""

# --- Signature -------------------------------------------------------------
Emit "## Signature numerique"
Emit ""
if ($item.Extension -in @('.exe','.dll','.msi','.sys','.ps1','.cab')) {
    $sig = Get-AuthenticodeSignature -FilePath $Target
    Emit "- Statut : **$($sig.Status)**"
    if ($sig.SignerCertificate) {
        Emit "- Signataire : $($sig.SignerCertificate.Subject)"
        Emit "- Emetteur   : $($sig.SignerCertificate.Issuer)"
        Emit "- Valide du  : $($sig.SignerCertificate.NotBefore) au $($sig.SignerCertificate.NotAfter)"
    } else {
        Emit "- **Non signe.** Tres courant pour un jeu indie : ce n'est pas une preuve"
        Emit "  de malveillance, mais ca supprime toute garantie sur l'auteur."
    }
} else {
    Emit "_Type de fichier non signable (archive)._"
}
Emit ""

# --- Contenu d'archive (SANS extraction) -----------------------------------
if ($item.Extension -eq '.zip') {
    Emit "## Contenu de l'archive (liste seule, aucune extraction)"
    Emit ""
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Target)
        $entries = $zip.Entries
        Emit "- $($entries.Count) entree(s)"
        Emit ""

        $risky = $entries | Where-Object { [System.IO.Path]::GetExtension($_.Name).ToLower() -in $RISKY }
        if ($risky) {
            Emit "### Fichiers executables / scriptables ($($risky.Count))"
            Emit ""
            Emit "| Taille | Chemin dans l'archive |"
            Emit "|---:|---|"
            $risky | Sort-Object Length -Descending | ForEach-Object {
                Emit "| $([math]::Round($_.Length/1KB,1)) Ko | ``$($_.FullName)`` |"
            }
            Emit ""
        }

        # Heuristiques bon marche mais qui attrapent des vrais cas
        $flags = New-Object System.Collections.Generic.List[string]
        foreach ($e in $entries) {
            $n = $e.FullName
            if ($n -match '\.\.[\\/]')                { $flags.Add("Traversee de chemin (Zip Slip) : ``$n``") }
            if ($n -match '\.(exe|scr|com|bat|cmd)$' -and $n -match '\.(txt|pdf|jpg|png|doc|mp4)\.') {
                                                        $flags.Add("Double extension trompeuse : ``$n``") }
            if ($n -match '(?i)(autorun\.inf|desktop\.ini)$') { $flags.Add("Fichier d'auto-execution : ``$n``") }
            if ($n -match '(?i)^\s*$|[‮​‎‏]') { $flags.Add("Caractere Unicode d'inversion/invisible dans le nom : ``$n``") }
            if ($e.Length -gt 0 -and $e.CompressedLength -gt 0 -and ($e.Length / $e.CompressedLength) -gt 500) {
                                                        $flags.Add("Ratio de compression extreme (zip bomb ?) : ``$n``") }
        }
        if ($flags.Count) {
            Emit "### ALERTES STRUCTURELLES"
            Emit ""
            $flags | Select-Object -Unique | ForEach-Object { Emit "- $_" }
            Emit ""
        } else {
            Emit "_Aucune anomalie structurelle detectee dans l'archive._"
            Emit ""
        }
    } catch {
        Emit "_Lecture de l'archive impossible : $($_.Exception.Message)_"
        Emit ""
    } finally { if ($zip) { $zip.Dispose() } }
}

# --- Defender ---------------------------------------------------------------
Emit "## Microsoft Defender - scan a la demande"
Emit ""
if ($NoDefenderScan) {
    Emit "_Ignore (-NoDefenderScan)._"
} else {
    $plat = Get-ChildItem "$env:ProgramData\Microsoft\Windows Defender\Platform" -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
    $mp = if ($plat) { Join-Path $plat.FullName 'MpCmdRun.exe' } else { "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" }

    if (Test-Path $mp) {
        Write-Host "[..] Scan Defender en cours..." -ForegroundColor Gray
        $out = & $mp -Scan -ScanType 3 -File $Target -DisableRemediation 2>&1 | Out-String
        Emit "``````"
        Emit ($out.Trim())
        Emit "``````"
        $det = Get-MpThreatDetection -ErrorAction SilentlyContinue |
               Where-Object { $_.Resources -match [regex]::Escape($item.Name) }
        if ($det) {
            Emit ""
            Emit "### MENACE DETECTEE"
            Emit ""
            $det | ForEach-Object { Emit "- $($_.ThreatID) / $($_.Resources -join ', ')" }
        }
    } else {
        Emit "_MpCmdRun.exe introuvable, scan ignore._"
    }
}
Emit ""

Emit "---"
Emit ""
Emit "> Un triage propre ne prouve RIEN. Defender ne connait pas un binaire compile"
Emit "> hier, et un jeu indie legitime est presque toujours non signe. La seule reponse"
Emit "> fiable est l'execution observee : ``.\New-SandboxRun.ps1``"

# --- Sauvegarde -------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $Root "reports\triage-$($item.BaseName)-$stamp.md"
New-Item -ItemType Directory -Path (Split-Path $outFile) -Force | Out-Null
$lines -join "`r`n" | Set-Content -Path $outFile -Encoding UTF8
Write-Host "`n[ok] Rapport : $outFile`n" -ForegroundColor Green
