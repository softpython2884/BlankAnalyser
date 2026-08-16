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
    foreach ($it in $items) {
        Write-Host "    -> $($it.Name)" -ForegroundColor Gray
        try { Copy-Item -LiteralPath $it.FullName -Destination $targetDir -Recurse -Force -ErrorAction Stop }
        catch { Warn "Copie de $($it.Name) impossible : $($_.Exception.Message)" }
    }
    Ok "$($items.Count) element(s) copie(s) BRUTS dans C:\Work\target."
    Ok "Decompile le .zip et lance l'executable directement depuis la."
}

# --- 2. Raccourcis sur le bureau (EN DEUXIEME, toujours) --------------------
Step "Raccourcis sur le bureau"
$desktop = [Environment]::GetFolderPath('Desktop')
try {
    @"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoExit -File "$Kit\Guest-Report.ps1"
"@ | Set-Content "$desktop\RAPPORT.cmd" -Encoding ASCII
    @"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoExit -File "$Kit\Guest-View.ps1"
"@ | Set-Content "$desktop\VOIR-UN-FICHIER.cmd" -Encoding ASCII
    Ok "RAPPORT.cmd et VOIR-UN-FICHIER.cmd sur le bureau."
} catch { Warn "Creation des raccourcis impossible : $($_.Exception.Message)" }

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

  Tes fichiers sont dans  C:\Work\target  (bruts, tels quels).

  ORDRE IMPORTANT -- le rapport n'a de sens qu'APRES avoir joue :

  1) Va dans  C:\Work\target . Decompile le .zip si besoin
     (clic droit > Extraire tout), puis lance l'executable.

  2) UTILISE-LE quelques minutes : menus, options, sauvegarde.
     Beaucoup de charges n'agissent qu'apres une interaction.

  3) SEULEMENT ENSUITE, double-clique  RAPPORT.cmd  sur le bureau.
     (Tu peux jouer plus et relancer RAPPORT.cmd autant de fois
      que tu veux : l'observation reste active.)

  Lire un fichier (pas de Notepad ici) : VOIR-UN-FICHIER.cmd

  Le rapport sort dans C:\BA\out\ = ton dossier reports\ sur l'hote.
================================================================
  Reseau : $(if ((Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')) {'ACTIF'} else {'COUPE'})   |   tout s'efface a la fermeture
================================================================

"@ -ForegroundColor White

try { Stop-Transcript | Out-Null } catch { }
Set-Location $targetDir -ErrorAction SilentlyContinue
