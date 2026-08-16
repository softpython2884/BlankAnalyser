<#
    BlankAnalyser - extracteur DIAGNOSTIC pour la sandbox.

    Windows Explorer extrait un zip et s'arrete SILENCIEUSEMENT a la premiere
    erreur (souvent : plus de place, ou une entree qui echoue). Ici on extrait
    fichier par fichier en CAPTURANT chaque erreur, on verifie l'espace disque
    et l'empreinte, et on extrait vers un chemin COURT (C:\g) pour ecarter tout
    probleme de longueur de chemin. Bref : on montre EXACTEMENT ce qui se passe.
#>
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

function Sep { Write-Host ("=" * 66) -ForegroundColor Cyan }

Clear-Host
Sep
Write-Host "  BlankAnalyser - extracteur diagnostic" -ForegroundColor Cyan
Sep

# --- Trouver les zips (copie dans C:\Work\target ET original dans C:\BA\in) --
$zips = @()
foreach ($dir in 'C:\Work\target', 'C:\BA\in') {
    if (Test-Path $dir) {
        $zips += Get-ChildItem $dir -Recurse -Filter *.zip -ErrorAction SilentlyContinue |
                 Where-Object { $_.Length -gt 0 }
    }
}
$zips = @($zips | Sort-Object FullName -Unique)
if (-not $zips) { Write-Host "`n  Aucun .zip trouve dans C:\Work\target ni C:\BA\in.`n" -ForegroundColor Yellow; return }

Write-Host "`n  Quel zip extraire ?`n" -ForegroundColor White
for ($i = 0; $i -lt $zips.Count; $i++) {
    Write-Host ("   {0,2}. {1,8} Mo  {2}" -f ($i+1), [math]::Round($zips[$i].Length/1MB,1), $zips[$i].FullName)
}
Write-Host ""
$sel = Read-Host "  Numero"
if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $zips.Count) { Write-Host "  Annule."; return }
$zip = $zips[[int]$sel - 1]

# --- Diagnostic prealable ---------------------------------------------------
Sep
Write-Host "  Source  : $($zip.FullName)"
Write-Host "  Taille  : $([math]::Round($zip.Length/1MB,1)) Mo"
Write-Host "  [..] SHA-256 (compare-le a l'empreinte donnee par le triage sur l'hote)..." -ForegroundColor Gray
$hash = (Get-FileHash $zip.FullName -Algorithm SHA256).Hash
Write-Host "  SHA-256 : $hash" -ForegroundColor $(if($hash){'White'}else{'Red'})

$needed = 0
try {
    $za = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
    $needed = ($za.Entries | Measure-Object -Property Length -Sum).Sum
    $nfiles = @($za.Entries | Where-Object { -not $_.FullName.EndsWith('/') }).Count
    $za.Dispose()
    Write-Host "  Contenu : $nfiles fichier(s), $([math]::Round($needed/1MB,1)) Mo une fois decompresse"
} catch {
    Write-Host "  [!] Impossible de lire l'index du zip : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      => le zip est probablement CORROMPU ou TRONQUE dans la sandbox." -ForegroundColor Red
    Write-Host "      Compare le SHA-256 ci-dessus avec celui de l'hote." -ForegroundColor Yellow
    return
}

$free = (Get-PSDrive C).Free
Write-Host "  Espace libre sur C: : $([math]::Round($free/1MB,1)) Mo" -ForegroundColor $(if ($free -gt $needed*1.2) {'Green'} else {'Red'})
if ($free -lt $needed * 1.2) {
    Write-Host "  [!] ESPACE INSUFFISANT : il faut ~$([math]::Round($needed*1.2/1MB,1)) Mo." -ForegroundColor Red
    Write-Host "      C'est tres probablement LA cause du 'un seul fichier'." -ForegroundColor Red
    Write-Host "      -> Relance la sandbox avec plus de RAM (menu option 4), ou" -ForegroundColor Yellow
    Write-Host "         teste un logiciel plus petit." -ForegroundColor Yellow
    $go = Read-Host "  Tenter quand meme ? (o/N)"
    if ($go -notmatch '^[oOyY]') { return }
}

# --- Extraction fichier par fichier, vers un chemin COURT -------------------
$destRoot = "C:\g\" + [System.IO.Path]::GetFileNameWithoutExtension($zip.Name)
if (Test-Path $destRoot) {
    Write-Host "`n  $destRoot existe deja." -ForegroundColor Yellow
    if ((Read-Host "  L'ecraser ? (o/N)") -match '^[oOyY]') { Remove-Item $destRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
New-Item -ItemType Directory -Path $destRoot -Force | Out-Null

Write-Host "`n  [..] Extraction vers $destRoot ..." -ForegroundColor Gray
$ok = 0; $fail = 0; $errs = New-Object System.Collections.Generic.List[string]
$za = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
try {
    foreach ($e in $za.Entries) {
        $out = Join-Path $destRoot $e.FullName
        if ($e.FullName.EndsWith('/')) { New-Item -ItemType Directory $out -Force -ErrorAction SilentlyContinue | Out-Null; continue }
        try {
            $parent = Split-Path $out -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory $parent -Force | Out-Null }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $out, $true)
            $ok++
            Write-Host ("    ok  {0,7} Mo  {1}" -f [math]::Round($e.Length/1MB,1), $e.Name) -ForegroundColor DarkGray
        } catch {
            $fail++
            $msg = "$($e.FullName) : $($_.Exception.Message)"
            $errs.Add($msg)
            Write-Host "    ECHEC  $msg" -ForegroundColor Red
        }
    }
} finally { $za.Dispose() }

Sep
if ($fail -eq 0) {
    Write-Host "  [OK] $ok fichier(s) extrait(s) sans erreur." -ForegroundColor Green
    Write-Host "  Ton logiciel est ici : $destRoot" -ForegroundColor Cyan
    Write-Host "  (chemin court, tu peux lancer l'executable de la)." -ForegroundColor Gray
} else {
    Write-Host "  [!] $ok reussi(s), $fail EN ECHEC." -ForegroundColor Yellow
    Write-Host "  Premieres erreurs (dis-les a l'assistant, elles donnent la cause) :" -ForegroundColor Yellow
    $errs | Select-Object -First 6 | ForEach-Object { Write-Host "     - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  'There is not enough space' -> RAM/disque sandbox trop petits." -ForegroundColor Gray
    Write-Host "  'did not match' / CRC        -> le zip est corrompu dans la sandbox" -ForegroundColor Gray
    Write-Host "                                  (compare le SHA-256 avec l'hote)." -ForegroundColor Gray
}
Sep
Write-Host ""
