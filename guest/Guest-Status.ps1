<#
    BlankAnalyser - etat de l'environnement de la sandbox.

    Repond a "le VC++ est-il installe ? en cours ? en echec ?", et donne les
    autres infos utiles quand quelque chose cloche (surveillance, disque, RAM,
    journal de demarrage).
#>
$ErrorActionPreference = 'Continue'
function Sep { Write-Host ("=" * 66) -ForegroundColor Cyan }
function Row($ok, $label, $val) {
    $tag = if ($ok) { '[ OK ]' } else { '[ !! ]' }
    $col = if ($ok) { 'Green' } else { 'Yellow' }
    Write-Host "  $tag " -ForegroundColor $col -NoNewline
    Write-Host ("{0,-30}" -f $label) -NoNewline
    Write-Host $val -ForegroundColor $col
}

Clear-Host
Sep
Write-Host "  BlankAnalyser - etat de la sandbox" -ForegroundColor Cyan
Sep

# --- Visual C++ -------------------------------------------------------------
Write-Host "`n  RUNTIMES VISUAL C++" -ForegroundColor White
$dll64 = Test-Path "$env:SystemRoot\System32\VCRUNTIME140.dll"
$dll86 = Test-Path "$env:SystemRoot\SysWOW64\VCRUNTIME140.dll"
Row $dll64 "VCRUNTIME140.dll (x64)" $(if ($dll64) { 'present -> jeux 64 bits OK' } else { 'MANQUANT' })
Row $dll86 "VCRUNTIME140.dll (x86)" $(if ($dll86) { 'present -> jeux 32 bits OK' } else { 'manquant (ok si jeu 64 bits)' })

# Entrees "Programmes installes" correspondantes
$vc = @()
foreach ($p in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    $vc += Get-ItemProperty $p -ErrorAction SilentlyContinue |
           Where-Object { $_.DisplayName -match 'Visual C\+\+.*Redistributable' } |
           Select-Object -ExpandProperty DisplayName
}
if ($vc) {
    Write-Host "        Detectes :" -ForegroundColor Gray
    $vc | Select-Object -Unique | ForEach-Object { Write-Host "          - $_" -ForegroundColor DarkGray }
} else {
    Write-Host "        (aucune entree 'Programmes installes' -- normal si l'install" -ForegroundColor DarkGray
    Write-Host "         a echoue ou tourne encore ; regarde le journal plus bas)" -ForegroundColor DarkGray
}

# Le processus d'install tourne-t-il encore ?
$running = Get-Process -Name 'vc_redist*','vcredist*','VC_redist*' -ErrorAction SilentlyContinue
if ($running) { Row $false "Installation VC++" "EN COURS ($($running.Count) processus)..." }

# --- Windows Defender -------------------------------------------------------
Write-Host "`n  WINDOWS DEFENDER (dans la sandbox)" -ForegroundColor White
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Row (-not $mp.RealTimeProtectionEnabled) "Protection temps reel" `
        $(if ($mp.RealTimeProtectionEnabled) { 'ACTIVE -- peut supprimer les .exe/.dll du jeu' } else { 'desactivee (normal ici : la VM est le confinement)' })
    $det = @(Get-MpThreatDetection -ErrorAction SilentlyContinue)
    if ($det) {
        Write-Host "        Fichiers signales/supprimes par Defender :" -ForegroundColor Yellow
        $det | Sort-Object InitialDetectionTime -Descending | Select-Object -First 8 | ForEach-Object {
            $res = (@($_.Resources) -join ', ') -replace '^file:_',''
            Write-Host "          - $res" -ForegroundColor DarkYellow
        }
        Write-Host "        (c'est un SIGNAL, pas une preuve : les cracks sont souvent" -ForegroundColor DarkGray
        Write-Host "         detectes comme 'HackTool' sans etre forcement un virus)" -ForegroundColor DarkGray
    } else {
        Write-Host "        (aucune detection enregistree)" -ForegroundColor DarkGray
    }
} catch { Write-Host "        (etat Defender indisponible : $($_.Exception.Message))" -ForegroundColor DarkGray }

# --- Surveillance -----------------------------------------------------------
Write-Host "`n  SURVEILLANCE" -ForegroundColor White
$svc = Get-Service -Name 'WinHostSvc','Sysmon64','Sysmon' -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running'
Row ([bool]$svc) "Observateur (Sysmon)" $(if ($svc) { "actif : $($svc.Name -join ', ')" } else { 'INACTIF -- le rapport dira "aucun journal"' })

# --- Ressources -------------------------------------------------------------
Write-Host "`n  RESSOURCES" -ForegroundColor White
$free = (Get-PSDrive C).Free / 1MB
$os = Get-CimInstance Win32_OperatingSystem
$ramFree = $os.FreePhysicalMemory / 1KB
$ramTot  = $os.TotalVisibleMemorySize / 1KB
Row ($free -gt 800) "Espace libre sur C:" "$([math]::Round($free)) Mo"
Row ($ramFree -gt 400) "RAM libre" "$([math]::Round($ramFree)) / $([math]::Round($ramTot)) Mo"
Write-Host "        (extraire un gros jeu demande de la place ET de la RAM :" -ForegroundColor DarkGray
Write-Host "         si c'est juste, relance la sandbox avec plus de RAM)" -ForegroundColor DarkGray

# --- Fichiers deployes ------------------------------------------------------
Write-Host "`n  FICHIERS A TESTER (C:\Work\target)" -ForegroundColor White
if (Test-Path 'C:\Work\target') {
    $f = @(Get-ChildItem 'C:\Work\target' -ErrorAction SilentlyContinue)
    if ($f) { $f | ForEach-Object { Write-Host "     $($_.Name)" -ForegroundColor DarkGray } }
    else { Write-Host "     (vide)" -ForegroundColor Yellow }
} else { Write-Host "     C:\Work\target n'existe pas (le bootstrap a echoue ?)" -ForegroundColor Red }

# --- Journal du bootstrap ---------------------------------------------------
Write-Host "`n  JOURNAL DE DEMARRAGE (dernieres lignes)" -ForegroundColor White
$log = 'C:\BA\out\_bootstrap.log'
if (Test-Path $log) {
    Get-Content $log -Tail 15 | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
    Write-Host "     (journal complet : reports\_bootstrap.log sur ton PC)" -ForegroundColor Gray
} else { Write-Host "     (pas de journal -- version ancienne du bootstrap ?)" -ForegroundColor Yellow }

Write-Host ""
Sep
Write-Host "  Pour extraire un gros zip proprement : EXTRAIRE.cmd" -ForegroundColor Cyan
Sep
Write-Host ""
