<#
    BlankAnalyser - lance automatiquement au demarrage de la sandbox.

    Ordre pense pour la ROBUSTESSE : on met d'abord les fichiers a tester et les
    raccourcis en place (etapes rapides et sures), PUIS on arme la surveillance,
    PUIS on installe les runtimes (etape qui peut trainer). Ainsi, meme si une
    installation bloque, l'essentiel est deja pret. Un journal est ecrit sur
    l'hote (reports\_bootstrap.log) pour diagnostiquer tout blocage.
#>
param(
    [string]$TargetName,
    [switch]$Stealth
)

$ErrorActionPreference = 'Continue'
$Work  = 'C:\Work'
$Kit   = 'C:\BA\kit'
$Cache = 'C:\BA\cache'
$In    = 'C:\BA\in'
$Out   = 'C:\BA\out'

function Step($m) { Write-Host "`n[.] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

New-Item -ItemType Directory -Path $Work -Force | Out-Null

# Journal sur l'hote : si le bootstrap se fige, on saura ou.
try { Start-Transcript -Path (Join-Path $Out '_bootstrap.log') -Force -ErrorAction Stop | Out-Null } catch { }

Clear-Host
Write-Host @"
================================================================
   BlankAnalyser  -  bac a sable d'analyse comportementale
================================================================
  Tu es dans une machine jetable. Rien ici n'atteint ton PC.
  A la fermeture de cette fenetre Sandbox, TOUT est detruit.
================================================================
"@ -ForegroundColor Cyan

# --- 1. Deploiement des fichiers a tester (EN PREMIER, toujours) ------------
#  On copie TOUT le contenu de la quarantaine, BRUT, sans rien extraire.
#  Tu retrouves tes fichiers tels quels dans C:\Work\target et tu decompiles
#  / lances ce que tu veux toi-meme.
Step "Mise en place de tes fichiers dans C:\Work\target"
$targetDir = Join-Path $Work 'target'
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
$items = @(Get-ChildItem $In -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.gitkeep' })
if (-not $items) {
    Warn "Aucun fichier dans C:\BA\in. La quarantaine est-elle vide ?"
} else {
    $big = @()
    foreach ($it in $items) {
        # Les gros fichiers (>150 Mo) ne sont PAS copies : copie lente sur le
        # partage, et double la place disque. On les laisse dans C:\BA\in ;
        # EXTRAIRE.cmd sait les lire directement de la.
        if (-not $it.PSIsContainer -and $it.Length -gt 150MB) {
            $big += $it.Name
            Write-Host "    (garde dans C:\BA\in) $($it.Name) [$([math]::Round($it.Length/1MB)) Mo]" -ForegroundColor DarkGray
            continue
        }
        Write-Host "    -> $($it.Name)" -ForegroundColor Gray
        try { Copy-Item -LiteralPath $it.FullName -Destination $targetDir -Recurse -Force -ErrorAction Stop }
        catch { Warn "Copie de $($it.Name) impossible : $($_.Exception.Message)" }
    }
    Ok "Fichiers dans C:\Work\target (decompile / lance depuis la)."
    if ($big) {
        Warn "Gros fichier(s) laisse(s) dans C:\BA\in : $($big -join ', ')"
        Warn "-> utilise EXTRAIRE.cmd (bureau) pour les extraire proprement."
    }
}

# --- 2. Raccourcis sur le bureau (EN DEUXIEME, toujours) --------------------
Step "Raccourcis sur le bureau"
$desktop = [Environment]::GetFolderPath('Desktop')
function Shortcut($name, $script) {
    @"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoExit -File "$Kit\$script"
"@ | Set-Content "$desktop\$name" -Encoding ASCII
}
try {
    Shortcut 'RAPPORT.cmd'         'Guest-Report.ps1'
    Shortcut 'EXTRAIRE.cmd'        'Guest-Extract.ps1'
    Shortcut 'VOIR-UN-FICHIER.cmd' 'Guest-View.ps1'
    Shortcut 'ETAT.cmd'            'Guest-Status.ps1'
    Ok "Bureau : RAPPORT / EXTRAIRE / VOIR-UN-FICHIER / ETAT"
} catch { Warn "Creation des raccourcis impossible : $($_.Exception.Message)" }

# --- 2b. Neutraliser Defender DANS la sandbox ------------------------------
#  Defender (actif dans la sandbox) supprime a l'ecriture les .exe/.dll qu'il
#  juge suspects -- typiquement les cracks Steam d'un jeu -- ce qui EMPECHE
#  l'extraction et l'execution, donc l'observation. Or la sandbox EST le
#  confinement (VM materielle, rien n'atteint l'hote). On neutralise donc
#  Defender ICI pour laisser le programme tourner et Sysmon voir son VRAI
#  comportement. L'avis "antivirus" se prend AVANT, au triage sur l'hote.
Step "Neutralisation de Defender (sandbox jetable seulement)"
try {
    Add-MpPreference -ExclusionPath 'C:\Work','C:\g','C:\BA' -ErrorAction SilentlyContinue
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    $rt = (Get-MpComputerStatus -ErrorAction SilentlyContinue).RealTimeProtectionEnabled
    if ($rt) {
        Warn "Defender temps reel TOUJOURS actif (protection contre la falsification ?)."
        Warn "Si l'extraction perd des .exe/.dll : Securite Windows > Protection contre"
        Warn "les virus > Parametres > desactive 'Protection en temps reel', puis re-extrais."
    } else {
        Ok "Defender temps reel desactive : les executables ne seront plus manges."
    }
} catch { Warn "Reglage Defender impossible : $($_.Exception.Message)" }

# --- 3. Camouflage (mode furtif) -------------------------------------------
if ($Stealth) {
    Step "Camouflage du bac a sable (mode furtif)"
    $realism = Join-Path $Kit 'Guest-Realism.ps1'
    if (Test-Path $realism) {
        try { & $realism } catch { Warn "Camouflage partiel : $($_.Exception.Message)" }
    } else { Warn "Guest-Realism.ps1 introuvable dans le kit." }
    Warn "RAPPEL : camouflage PARTIEL. Le processeur virtualise et le compte"
    Warn "WDAGUtilityAccount trahissent toujours la VM (docs/ANTI-VM.md)."
}

# --- 4. Surveillance --------------------------------------------------------
Step "Armement de la surveillance"
$monitorMode = 'none'
$sysmon = Join-Path $Cache 'tools\Sysmon64.exe'
$cfg    = Join-Path $Kit 'sysmon-blankanalyser.xml'
$sysmonBin = $null

if ((Test-Path $sysmon) -and (Test-Path $cfg)) {
    # Sysmon ecrit un driver : on le copie hors du montage lecture seule.
    # En mode furtif on renomme le binaire -> service et processus non nommes
    # "Sysmon" (le driver reste "SysmonDrv", cf docs/ANTI-VM.md).
    try {
        $binName = if ($Stealth) { 'WinHostSvc.exe' } else { 'Sysmon64.exe' }
        $svcName = [System.IO.Path]::GetFileNameWithoutExtension($binName)
        $local = Join-Path $Work $binName
        Copy-Item $sysmon $local -Force
        $sysmonBin = $local
        $r = & $local -accepteula -i $cfg 2>&1 | Out-String
        Start-Sleep -Seconds 2
        if (Get-Service -Name $svcName, 'Sysmon64', 'Sysmon' -ErrorAction SilentlyContinue) {
            $monitorMode = 'sysmon'
            if ($Stealth) { Ok "Observation active (service masque sous '$svcName')." }
            else { Ok "Sysmon actif - journalisation structuree du comportement." }
        } else {
            Warn "L'observateur n'a pas demarre. Sortie :"
            Write-Host $r -ForegroundColor DarkGray
        }
    } catch { Warn "Armement Sysmon impossible : $($_.Exception.Message)" }
}
else { Warn "Sysmon absent de cache\tools\ (lance Setup-Host.ps1 sur l'hote)." }

if ($monitorMode -eq 'none') {
    Warn "Bascule sur le moniteur de secours (PowerShell pur, sans driver)."
    try {
        Start-Process powershell.exe -ArgumentList @(
            '-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
            '-File',"$Kit\Guest-FallbackMonitor.ps1"
        )
        Start-Sleep -Seconds 2
        $monitorMode = 'fallback'
        Ok "Moniteur de secours actif."
    } catch { Warn "Moniteur de secours impossible : $($_.Exception.Message)" }
}

# --- 5. Runtimes depuis le cache (EN DERNIER : peut trainer) ----------------
#  Avec un DELAI MAXIMAL par installeur : un runtime qui bloque ne doit JAMAIS
#  geler toute la sandbox (c'etait le bug du "rien ne se passe").
Step "Installation des runtimes (VC++...) depuis le cache"
$redist = @(Get-ChildItem "$Cache\redist" -Filter *.exe -ErrorAction SilentlyContinue)
if (-not $redist) {
    Warn "cache\redist\ vide. Si un jeu reclame VCRUNTIME140.dll / MSVCP140.dll,"
    Warn "relance Setup-Host.ps1 sur l'hote (il telecharge le VC++ tout seul)."
} else {
    foreach ($rd in $redist) {
        Write-Host "    -> $($rd.Name)" -ForegroundColor Gray
        try {
            $proc = Start-Process -FilePath $rd.FullName `
                    -ArgumentList '/install','/quiet','/norestart' -PassThru -ErrorAction Stop
            if ($proc.WaitForExit(120000)) {          # 2 min max par installeur
                if ($proc.ExitCode -in 0, 1638, 3010) { Ok "$($rd.Name) : ok (code $($proc.ExitCode))" }
                else { Warn "$($rd.Name) : code $($proc.ExitCode)" }
            } else {
                Warn "$($rd.Name) : trop long (>2 min), on continue sans attendre."
                try { $proc.Kill() } catch { }
            }
        } catch { Warn "$($rd.Name) : $($_.Exception.Message)" }
    }
}

# --- 6. Marqueur de session -------------------------------------------------
[PSCustomObject]@{
    Start      = (Get-Date).ToString('o')
    Target     = $TargetName
    Monitor    = $monitorMode
    WorkDir    = $targetDir
    Stealth    = [bool]$Stealth
    SysmonBin  = $sysmonBin
} | ConvertTo-Json | Set-Content "$Work\_session.json" -Encoding UTF8

# --- 7. Instructions --------------------------------------------------------
Write-Host @"

================================================================
  PRET.  Surveillance : $monitorMode
================================================================

  Tes petits fichiers sont dans  C:\Work\target . Les gros zips
  restent dans  C:\BA\in  (voir plus bas).

  ORDRE IMPORTANT -- le rapport n'a de sens qu'APRES avoir joue :

  1) EXTRAIRE le jeu : double-clique  EXTRAIRE.cmd  sur le bureau.
     Il extrait proprement (vers C:\g), verifie la place disque et
     dit exactement si un fichier echoue. NE decompresse PAS un gros
     zip avec le clic-droit Windows : il s'arrete en silence.

  2) Lance l'executable extrait, et UTILISE-LE quelques minutes.

  3) SEULEMENT ENSUITE, double-clique  RAPPORT.cmd .
     (Rejouable autant de fois que tu veux : l'observation reste active.)

  Autres outils du bureau :
    ETAT.cmd            -> VC++ installe ? disque/RAM ? journal ?
    VOIR-UN-FICHIER.cmd -> lire un fichier (pas de Notepad ici)

  Le rapport sort dans C:\BA\out\ = ton dossier reports\ sur l'hote.
================================================================
  Reseau : $(if ((Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')) {'ACTIF'} else {'COUPE'})   |   tout s'efface a la fermeture
================================================================

"@ -ForegroundColor White

try { Stop-Transcript | Out-Null } catch { }
Set-Location $targetDir -ErrorAction SilentlyContinue
