<#
    BlankAnalyser - lance automatiquement au demarrage de la sandbox.
    Prepare l'environnement, installe les dependances depuis le cache, arme
    la surveillance, puis rend la main.
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

Clear-Host
Write-Host @"
================================================================
   BlankAnalyser  -  bac a sable d'analyse comportementale
================================================================
  Tu es dans une machine jetable. Rien ici n'atteint ton PC.
  A la fermeture de cette fenetre Sandbox, TOUT est detruit.
================================================================
"@ -ForegroundColor Cyan

New-Item -ItemType Directory -Path $Work -Force | Out-Null

# --- 1. Dependances depuis le cache (zero telechargement) -------------------
Step "Installation des dependances depuis le cache local"
$redist = Get-ChildItem "$Cache\redist" -Filter *.exe -ErrorAction SilentlyContinue
if (-not $redist) {
    Warn "cache\redist\ est vide - aucune dependance a installer."
    Warn "Si le jeu se plaint d'un VCRUNTIME140.dll ou MSVCP140.dll manquant,"
    Warn "mets vc_redist.x64.exe dans cache\redist\ sur l'hote et relance."
} else {
    foreach ($r in $redist) {
        Write-Host "    -> $($r.Name)" -ForegroundColor Gray
        try {
            $p = Start-Process -FilePath $r.FullName -ArgumentList '/install','/quiet','/norestart' `
                               -Wait -PassThru -ErrorAction Stop
            if ($p.ExitCode -in 0, 1638, 3010) { Ok "$($r.Name) : ok (code $($p.ExitCode))" }
            else { Warn "$($r.Name) : code $($p.ExitCode)" }
        } catch { Warn "$($r.Name) : $($_.Exception.Message)" }
    }
}

# --- 1b. Couche de camouflage (mode furtif) --------------------------------
#  IMPORTANT : elle tourne AVANT l'armement de l'observateur, pour que les faux
#  fichiers/processus qu'elle cree ne polluent pas le rapport comportemental.
if ($Stealth) {
    Step "Camouflage du bac a sable (mode furtif)"
    $realism = Join-Path $Kit 'Guest-Realism.ps1'
    if (Test-Path $realism) {
        try { & $realism } catch { Warn "Camouflage partiel : $($_.Exception.Message)" }
    } else { Warn "Guest-Realism.ps1 introuvable dans le kit." }
    Warn "RAPPEL : le camouflage est partiel par conception. Un echantillon qui"
    Warn "teste le processeur ou le nom d'utilisateur verra quand meme une VM."
    Warn "Voir docs/ANTI-VM.md. Ne prends jamais un rapport propre pour une preuve."
}

# --- 2. Surveillance --------------------------------------------------------
Step "Armement de la surveillance"
$monitorMode = 'none'
$sysmon = Join-Path $Cache 'tools\Sysmon64.exe'
$cfg    = Join-Path $Kit 'sysmon-blankanalyser.xml'

$sysmonBin = $null
if ((Test-Path $sysmon) -and (Test-Path $cfg)) {
    # Sysmon a besoin d'ecrire son driver : on le copie hors du montage lecture seule.
    # En mode furtif on renomme le binaire : le nom du SERVICE et du PROCESSUS
    # derive du nom de l'executable, donc "Sysmon64.exe" -> un service et un
    # processus qui ne s'appellent plus "Sysmon" (le tell le plus courant).
    # NB : le DRIVER reste nomme "SysmonDrv" (non renommable en ligne de commande) ;
    # c'est une limite documentee dans docs/ANTI-VM.md.
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
}
else { Warn "Sysmon absent de cache\tools\ (lance Setup-Host.ps1 sur l'hote)." }

if ($monitorMode -eq 'none') {
    Warn "Bascule sur le moniteur de secours (PowerShell pur, sans driver)."
    Start-Process powershell.exe -ArgumentList @(
        '-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
        '-File',"$Kit\Guest-FallbackMonitor.ps1"
    )
    Start-Sleep -Seconds 2
    if (Test-Path "$Work\_fallback.jsonl") { $monitorMode = 'fallback'; Ok "Moniteur de secours actif." }
    else { Warn "Moniteur de secours en cours de demarrage..."; $monitorMode = 'fallback' }
}

# --- 3. Mise en place de la cible -------------------------------------------
Step "Deploiement de la cible"
$src = Join-Path $In $TargetName
if (-not (Test-Path $src)) {
    Warn "Cible '$TargetName' introuvable dans C:\BA\in. Contenu disponible :"
    Get-ChildItem $In -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "      $($_.Name)" }
} else {
    $item = Get-Item $src
    if ($item.PSIsContainer) {
        Copy-Item $src "$Work\target" -Recurse -Force
        Ok "Dossier copie dans C:\Work\target"
    }
    elseif ($item.Extension -eq '.zip') {
        Expand-Archive -Path $src -DestinationPath "$Work\target" -Force
        Ok "Archive extraite dans C:\Work\target"
    }
    else {
        New-Item -ItemType Directory -Path "$Work\target" -Force | Out-Null
        Copy-Item $src "$Work\target\" -Force
        Ok "Fichier copie dans C:\Work\target"
    }
}

# --- 4. Marqueur de depart --------------------------------------------------
[PSCustomObject]@{
    Start      = (Get-Date).ToString('o')
    Target     = $TargetName
    Monitor    = $monitorMode
    WorkDir    = "$Work\target"
    Stealth    = [bool]$Stealth
    SysmonBin  = $sysmonBin
} | ConvertTo-Json | Set-Content "$Work\_session.json" -Encoding UTF8

# --- 5. Raccourci rapport sur le bureau -------------------------------------
$desktop = [Environment]::GetFolderPath('Desktop')
@"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoExit -File "$Kit\Guest-Report.ps1"
"@ | Set-Content "$desktop\RAPPORT.cmd" -Encoding ASCII

# --- 6. Instructions --------------------------------------------------------
Write-Host @"

================================================================
  PRET.  Mode de surveillance : $monitorMode
================================================================

  1) Ouvre  C:\Work\target  et lance l'executable du jeu.

  2) JOUE / UTILISE-LE quelques minutes. Fais ce que tu ferais
     normalement : menus, sauvegarde, options. Beaucoup de malwares
     n'agissent qu'apres un delai ou une interaction.

  3) Ferme le programme, puis double-clique  RAPPORT.cmd  sur le
     bureau (ou tape la commande ci-dessous).

     Le rapport sort dans  C:\BA\out\  = ton dossier reports\ sur
     l'hote. Il survit a la fermeture de la sandbox.

  Commande manuelle du rapport :
     powershell -File $Kit\Guest-Report.ps1

================================================================
  Rappel : le reseau est $(if ((Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')) {'ACTIF'} else {'COUPE'}) dans cette sandbox.
================================================================

"@ -ForegroundColor White

Set-Location "$Work\target" -ErrorAction SilentlyContinue
