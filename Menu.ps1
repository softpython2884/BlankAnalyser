<#
    BlankAnalyser - menu interactif.
    Lance par BlankAnalyser.cmd. Ne pas executer directement (encodage console).
#>
[CmdletBinding()]
param([string]$InitialTarget = '')

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# --- Helpers d'affichage ----------------------------------------------------
function Line($c = '-', $n = 64) { Write-Host ('  ' + ($c * $n)) -ForegroundColor DarkGray }

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "                    B L A N K A N A L Y S E R" -ForegroundColor Cyan
    Write-Host "         Bac à sable jetable pour logiciels d'origine douteuse" -ForegroundColor DarkCyan
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-Quarantine {
    @(Get-ChildItem (Join-Path $Root 'quarantine') -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -ne '.gitkeep' })
}

function Get-State {
    $q = Get-Quarantine
    [PSCustomObject]@{
        Sandbox    = Test-Path "$env:SystemRoot\System32\WindowsSandbox.exe"
        Sysmon     = Test-Path (Join-Path $Root 'cache\tools\Sysmon64.exe')
        Redist     = @(Get-ChildItem (Join-Path $Root 'cache\redist') -Filter *.exe -ErrorAction SilentlyContinue).Count
        Targets    = $q
        Reports    = @(Get-ChildItem (Join-Path $Root 'reports') -Filter *.md -ErrorAction SilentlyContinue).Count
        FreeRamGB  = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    }
}

function Show-State($s) {
    function Row($ok, $label, $value) {
        $tag = if ($ok -eq 'ok') { '[ OK ]' } elseif ($ok -eq 'warn') { '[ !! ]' } else { '[ -- ]' }
        $col = if ($ok -eq 'ok') { 'Green' } elseif ($ok -eq 'warn') { 'Yellow' } else { 'DarkGray' }
        Write-Host "  $tag " -ForegroundColor $col -NoNewline
        Write-Host ("{0,-34}" -f $label) -NoNewline
        Write-Host $value -ForegroundColor $col
    }
    Write-Host "  ÉTAT" -ForegroundColor White
    Line
    Row $(if ($s.Sandbox) {'ok'} else {'warn'}) "Windows Sandbox" $(if ($s.Sandbox) {'installé'} else {'PAS INSTALLÉ  -> option 1'})
    Row $(if ($s.Sysmon)  {'ok'} else {'warn'}) "Outil d'observation (Sysmon)" $(if ($s.Sysmon) {'présent'} else {'MANQUANT  -> option 1'})
    Row $(if ($s.Redist -gt 0) {'ok'} else {'none'}) "Cache de dépendances" $(if ($s.Redist -gt 0) {"$($s.Redist) fichier(s)"} else {'vide (optionnel)'})
    Row $(if ($s.Targets.Count -gt 0) {'ok'} else {'none'}) "Fichiers en quarantaine" $(if ($s.Targets.Count -gt 0) {"$($s.Targets.Count)"} else {'aucun  -> option 2'})
    Row $(if ($s.Reports -gt 0) {'ok'} else {'none'}) "Rapports générés" "$($s.Reports)"
    Row $(if ($s.FreeRamGB -ge 3.5) {'ok'} elseif ($s.FreeRamGB -ge 2) {'warn'} else {'warn'}) "RAM libre" "$($s.FreeRamGB) Go"
    Write-Host ""
}

function Pause-Menu($msg = 'Appuie sur Entrée pour revenir au menu') {
    Write-Host ""
    Write-Host "  $msg" -ForegroundColor DarkGray
    [void](Read-Host)
}

function Ask($question, $default) {
    Write-Host "  $question " -NoNewline -ForegroundColor White
    Write-Host "[$default] " -NoNewline -ForegroundColor DarkGray
    $r = Read-Host
    if ([string]::IsNullOrWhiteSpace($r)) { return $default }
    return $r.Trim()
}

# --- Choix d'une cible ------------------------------------------------------
function Select-Target {
    $q = Get-Quarantine
    if (-not $q) {
        Write-Host ""
        Write-Host "  Aucun fichier en quarantaine." -ForegroundColor Yellow
        Write-Host "  Utilise l'option 2 pour en ajouter un." -ForegroundColor Yellow
        Pause-Menu
        return $null
    }
    Write-Host ""
    Write-Host "  QUEL FICHIER ?" -ForegroundColor White
    Line
    for ($i = 0; $i -lt $q.Count; $i++) {
        $sz = if ($q[$i].PSIsContainer) { '<dossier>' } else { "$([math]::Round($q[$i].Length/1MB,1)) Mo" }
        Write-Host ("   {0,2}. {1,-42} {2}" -f ($i + 1), $q[$i].Name, $sz)
    }
    Write-Host "    0. Annuler" -ForegroundColor DarkGray
    Write-Host ""
    $c = Read-Host "  Numéro"
    if ($c -notmatch '^\d+$' -or [int]$c -lt 1 -or [int]$c -gt $q.Count) { return $null }
    return $q[[int]$c - 1]
}

# --- Actions ----------------------------------------------------------------
function Invoke-Install {
    Show-Header
    Write-Host "  INSTALLATION" -ForegroundColor White
    Line
    Write-Host ""
    Write-Host "  Cette étape va :" -ForegroundColor Gray
    Write-Host "    - activer Windows Sandbox (nécessite les droits administrateur)" -ForegroundColor Gray
    Write-Host "    - télécharger Sysmon et Procmon (~10 Mo, UNE SEULE FOIS)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Une fenêtre séparée va s'ouvrir et demander l'autorisation" -ForegroundColor Yellow
    Write-Host "  administrateur. C'est normal." -ForegroundColor Yellow
    Write-Host ""
    if ((Ask 'Continuer ? (o/n)' 'o') -notmatch '^[oOyY]') { return }

    try {
        Start-Process powershell -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit',
            '-File', "`"$Root\Setup-Host.ps1`""
        )
        Write-Host ""
        Write-Host "  Fenêtre d'installation lancée." -ForegroundColor Green
        Write-Host "  Suis-la jusqu'au bout, puis reviens ici." -ForegroundColor Green
        Write-Host ""
        Write-Host "  IMPORTANT : si elle demande un redémarrage, redémarre avant" -ForegroundColor Yellow
        Write-Host "  d'utiliser le bac à sable pour la première fois." -ForegroundColor Yellow
    } catch {
        Write-Host ""
        Write-Host "  Élévation refusée ou impossible : $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause-Menu
}

function Invoke-AddTarget([string]$Preset = '') {
    Show-Header
    Write-Host "  AJOUTER UN FICHIER À ANALYSER" -ForegroundColor White
    Line
    Write-Host ""
    $path = $Preset
    if (-not $path) {
        Write-Host "  Glisse-dépose le fichier dans cette fenêtre (le chemin s'écrit" -ForegroundColor Gray
        Write-Host "  tout seul), ou colle son chemin, puis Entrée." -ForegroundColor Gray
        Write-Host ""
        $path = Read-Host "  Chemin"
    }
    $path = $path.Trim().Trim('"')
    if (-not $path) { return }

    if (-not (Test-Path $path)) {
        Write-Host ""
        Write-Host "  Introuvable : $path" -ForegroundColor Red
        Pause-Menu; return
    }

    $dest = Join-Path $Root 'quarantine'
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $name = Split-Path $path -Leaf
    try {
        Copy-Item -Path $path -Destination (Join-Path $dest $name) -Recurse -Force
        Write-Host ""
        Write-Host "  [OK] '$name' est en quarantaine." -ForegroundColor Green
        Write-Host "       Il n'a PAS été exécuté. Un fichier posé sur le disque" -ForegroundColor Gray
        Write-Host "       ne fait rien tant qu'on ne le lance pas." -ForegroundColor Gray
    } catch {
        Write-Host ""
        Write-Host "  Copie impossible : $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause-Menu
}

function Invoke-Triage {
    Show-Header
    Write-Host "  TRIAGE STATIQUE (aucune exécution)" -ForegroundColor White
    Line
    $t = Select-Target
    if (-not $t) { return }
    Write-Host ""
    try { & "$Root\Triage-Host.ps1" -Target $t.FullName }
    catch { Write-Host "  Erreur : $($_.Exception.Message)" -ForegroundColor Red }
    Pause-Menu
}

function Invoke-Run {
    Show-Header
    Write-Host "  LANCER DANS LE BAC À SABLE" -ForegroundColor White
    Line

    $s = Get-State
    if (-not $s.Sandbox) {
        Write-Host ""
        Write-Host "  Windows Sandbox n'est pas installé." -ForegroundColor Red
        Write-Host "  Fais l'option 1 d'abord (puis redémarre si demandé)." -ForegroundColor Yellow
        Pause-Menu; return
    }
    if (-not $s.Sysmon) {
        Write-Host ""
        Write-Host "  Sysmon est absent : l'analyse basculera en mode dégradé" -ForegroundColor Yellow
        Write-Host "  (pas de registre, pas d'accès disque brut)." -ForegroundColor Yellow
    }

    $t = Select-Target
    if (-not $t) { return }

    Write-Host ""
    Write-Host "  RÉGLAGES" -ForegroundColor White
    Line
    Write-Host ""
    Write-Host "  Réseau : coupé = le programme ne peut rien envoyer dehors." -ForegroundColor DarkGray
    Write-Host "           Fais toujours le premier essai réseau coupé." -ForegroundColor DarkGray
    $net = (Ask 'Ouvrir le réseau ? (o/n)' 'n') -match '^[oOyY]'

    Write-Host ""
    Write-Host "  vGPU : nécessaire pour la 3D, mais élargit la surface d'attaque." -ForegroundColor DarkGray
    $gpu = (Ask 'Activer le vGPU ? (o/n)' 'n') -match '^[oOyY]'

    Write-Host ""
    Write-Host "  Mode furtif : camoufle en partie le bac à sable pour que les" -ForegroundColor DarkGray
    Write-Host "  malwares qui 'se cachent en VM' se dévoilent. NE rend PAS invisible :" -ForegroundColor DarkGray
    Write-Host "  un échantillon déterminé verra toujours une VM (voir Aide)." -ForegroundColor DarkGray
    $stealth = (Ask 'Activer le mode furtif ? (o/n)' 'n') -match '^[oOyY]'

    Write-Host ""
    $maxSafe = [math]::Max(1536, [int](($s.FreeRamGB * 1024) - 1024))
    $suggest = [math]::Min(3072, $maxSafe)
    Write-Host "  RAM libre actuelle : $($s.FreeRamGB) Go." -ForegroundColor DarkGray
    $ramIn = Ask 'RAM pour le bac à sable (Mo)' "$suggest"
    $ram = 3072; if ($ramIn -match '^\d+$') { $ram = [int]$ramIn }
    if ($ram -lt 1024) { $ram = 1024 }; if ($ram -gt 8192) { $ram = 8192 }

    Write-Host ""
    Line '='
    Write-Host "  Cible  : $($t.Name)"
    Write-Host "  Réseau : $(if ($net) {'OUVERT'} else {'COUPÉ'})" -ForegroundColor $(if ($net) {'Yellow'} else {'Green'})
    Write-Host "  vGPU   : $(if ($gpu) {'activé'} else {'désactivé'})"
    Write-Host "  Furtif : $(if ($stealth) {'ACTIF'} else {'désactivé'})" -ForegroundColor $(if ($stealth) {'Yellow'} else {'Gray'})
    Write-Host "  RAM    : $ram Mo"
    Line '='
    Write-Host ""
    if ((Ask 'Lancer ? (o/n)' 'o') -notmatch '^[oOyY]') { return }

    # NB : ne pas nommer cette variable $args -- c'est une variable automatique
    $splat = @{ Target = $t.Name; MemoryMB = $ram }
    if ($net)     { $splat['Network'] = $true }
    if ($gpu)     { $splat['Gpu'] = $true }
    if ($stealth) { $splat['Stealth'] = $true }
    try {
        & "$Root\New-SandboxRun.ps1" @splat
        Write-Host ""
        Write-Host "  Dans la fenêtre du bac à sable :" -ForegroundColor White
        Write-Host "    1. ouvre C:\Work\target et lance le jeu" -ForegroundColor Gray
        Write-Host "    2. utilise-le vraiment quelques minutes" -ForegroundColor Gray
        Write-Host "    3. double-clique RAPPORT.cmd sur le bureau" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Le rapport arrivera dans reports\ (option 5)." -ForegroundColor Green
    } catch {
        Write-Host "  Erreur : $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause-Menu
}

function Invoke-Reports {
    Show-Header
    Write-Host "  RAPPORTS" -ForegroundColor White
    Line
    $rep = @(Get-ChildItem (Join-Path $Root 'reports') -Filter *.md -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending)
    if (-not $rep) {
        Write-Host ""
        Write-Host "  Aucun rapport pour l'instant." -ForegroundColor DarkGray
        Pause-Menu; return
    }
    Write-Host ""
    for ($i = 0; $i -lt [math]::Min($rep.Count, 15); $i++) {
        Write-Host ("   {0,2}. {1,-52} {2}" -f ($i + 1), $rep[$i].Name, $rep[$i].LastWriteTime.ToString('dd/MM HH:mm'))
    }
    Write-Host "    d. Ouvrir le dossier    0. Retour" -ForegroundColor DarkGray
    Write-Host ""
    $c = Read-Host "  Numéro"
    if ($c -eq 'd') { Start-Process explorer.exe (Join-Path $Root 'reports'); return }
    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $rep.Count) {
        Show-Header
        Get-Content $rep[[int]$c - 1].FullName | ForEach-Object {
            $l = $_
            if ($l -match 'VERDICT')          { Write-Host $l -ForegroundColor Yellow }
            elseif ($l -match '\[!!!\]')      { Write-Host $l -ForegroundColor Red }
            elseif ($l -match '\[!!\]')       { Write-Host $l -ForegroundColor Yellow }
            elseif ($l -match '^#')           { Write-Host $l -ForegroundColor Cyan }
            else                              { Write-Host $l }
        }
        Pause-Menu
    }
}

function Invoke-Help {
    Show-Header
    Write-Host @"
  COMMENT ÇA MARCHE
  ----------------------------------------------------------------

  Le principe : le programme douteux tourne dans une machine
  virtuelle jetable qui ne voit RIEN de ton PC. Pas tes clés SSH,
  pas ton profil navigateur, pas tes disques. À la fermeture,
  tout ce qu'il a fait est détruit avec elle.

  L'ORDRE À SUIVRE
  ----------------------------------------------------------------

    Option 1  une seule fois (redémarrage possible)
    Option 2  ajouter le .zip / .exe téléchargé
    Option 3  triage sans exécution : hash, signature, contenu
    Option 4  exécution observée dans le bac à sable
    Option 5  lire le rapport

  Premier essai TOUJOURS réseau coupé. Si c'est propre, refais
  un passage réseau ouvert pour voir qui il appelle.

  CE QUE ÇA GARANTIT, ET CE QUE ÇA NE GARANTIT PAS
  ----------------------------------------------------------------

  L'isolation est réelle : c'est une VM à frontière matérielle,
  pas un simple bridage. Un programme qui détruit tout ne détruit
  qu'un disque virtuel jetable.

  La détection, elle, n'est qu'un indice. Un malware peut repérer
  le bac à sable et rester sagement inerte, ou n'agir que dans
  plusieurs jours. Un rapport propre ne veut pas dire "sain" :
  ça veut dire "rien vu pendant ces quelques minutes".

  LE MODE FURTIF (option au lancement)
  ----------------------------------------------------------------

  Certains malwares vérifient s'ils tournent dans une VM et restent
  sages s'ils en détectent une. Le mode furtif camoufle les indices
  les plus faciles (session vide, service d'observation nommé
  "Sysmon", absence d'activité souris) pour les pousser à se dévoiler.

  MAIS il ne rend PAS la VM invisible, et il ne le peut pas : le
  processeur virtualisé et le compte "WDAGUtilityAccount" trahissent
  toujours Windows Sandbox à un échantillon sérieux. Un rapport propre
  en mode furtif reste un indice, jamais une preuve. Détails complets
  dans docs\ANTI-VM.md.

  CE QUI NE MARCHERA PAS
  ----------------------------------------------------------------

  Jeux à anti-triche noyau (EAC, BattlEye) : refusent les VM.
  Jeux 3D lourds : ton iGPU partagé et tes 8 Go de RAM ne suivront
  pas. Pour ceux-là, vois le README (compte Windows non-admin).

  ET SURTOUT
  ----------------------------------------------------------------

  Rien de tout ça ne remplace une SAUVEGARDE DÉBRANCHÉE.
  C'est la seule réponse au disque effacé.

"@ -ForegroundColor Gray
    Pause-Menu
}

# --- Glisser-déposer sur le .cmd -------------------------------------------
if ($InitialTarget -and (Test-Path $InitialTarget)) {
    Invoke-AddTarget -Preset $InitialTarget
}

# --- Boucle principale ------------------------------------------------------
while ($true) {
    try {
        Show-Header
        $state = Get-State
        Show-State $state

        Write-Host "  QUE VEUX-TU FAIRE ?" -ForegroundColor White
        Line
        Write-Host "   1. Installer / réparer BlankAnalyser" -NoNewline
        Write-Host "        (une seule fois)" -ForegroundColor DarkGray
        Write-Host "   2. Ajouter un fichier à analyser"
        Write-Host "   3. Triage rapide" -NoNewline
        Write-Host "                          (sans l'exécuter)" -ForegroundColor DarkGray
        Write-Host "   4. LANCER dans le bac à sable" -ForegroundColor Green -NoNewline
        Write-Host "           (exécution observée)" -ForegroundColor DarkGray
        Write-Host "   5. Lire les rapports"
        Write-Host "   6. Ouvrir le dossier quarantaine"
        Write-Host "   7. Aide"
        Write-Host "   0. Quitter" -ForegroundColor DarkGray
        Write-Host ""
        $choice = Read-Host "  Ton choix"

        switch ($choice.Trim()) {
            '1' { Invoke-Install }
            '2' { Invoke-AddTarget }
            '3' { Invoke-Triage }
            '4' { Invoke-Run }
            '5' { Invoke-Reports }
            '6' { Start-Process explorer.exe (Join-Path $Root 'quarantine') }
            '7' { Invoke-Help }
            '0' { Write-Host ""; exit 0 }
            ''  { }
            default {
                Write-Host "  Choix inconnu : '$choice'" -ForegroundColor DarkGray
                Start-Sleep -Milliseconds 900
            }
        }
    } catch {
        Write-Host ""
        Write-Host "  Une erreur est survenue : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Le menu continue." -ForegroundColor DarkGray
        Pause-Menu
    }
}
