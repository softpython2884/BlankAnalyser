<#
.SYNOPSIS
    BlankAnalyser - Genere et lance une sandbox d'analyse pour une cible donnee.
.DESCRIPTION
    Construit un fichier .wsb avec le cloisonnement voulu, puis demarre Windows Sandbox.

    Montages :
      guest\      -> C:\BA\kit    LECTURE SEULE
      cache\      -> C:\BA\cache  LECTURE SEULE   (redists + outils, pas de retelechargement)
      quarantine\ -> C:\BA\in     LECTURE SEULE   (la cible : le malware ne peut pas la modifier)
      reports\    -> C:\BA\out    ECRITURE        (seul canal retour, uniquement des .md/.csv)

.PARAMETER Target
    Nom du fichier/dossier DANS quarantine\ (pas un chemin complet).
.PARAMETER Network
    Active le reseau dans la sandbox. Par defaut COUPE.
.PARAMETER Gpu
    Active le vGPU (necessaire pour la 3D, mais elargit la surface d'attaque).
.EXAMPLE
    .\New-SandboxRun.ps1 -Target jeu.zip
    .\New-SandboxRun.ps1 -Target jeu.zip -Gpu -Network -MemoryMB 4096
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Target,
    [switch]$Network,
    [switch]$Gpu,
    [ValidateRange(1024, 8192)][int]$MemoryMB = 3072,
    [switch]$Stealth,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Verifications ----------------------------------------------------------
$sandboxExe = "$env:SystemRoot\System32\WindowsSandbox.exe"
if (-not (Test-Path $sandboxExe) -and -not $NoLaunch) {
    throw "Windows Sandbox n'est pas installe.`n" +
          "Lance d'abord Setup-Host.ps1 en administrateur (puis redemarre).`n" +
          "Pour seulement generer le .wsb sans lancer : ajoute -NoLaunch"
}

$targetPath = Join-Path $Root "quarantine\$Target"
if (-not (Test-Path $targetPath)) {
    throw "Cible introuvable : $targetPath`nDepose le fichier dans le dossier quarantine\ d'abord."
}

$free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB
if ($MemoryMB -gt ($free - 1024)) {
    Write-Host "[!] RAM libre : $([math]::Round($free)) Mo. Demander $MemoryMB Mo va faire ramer l'hote." -ForegroundColor Yellow
    Write-Host "    Ferme ton navigateur avant de lancer, ou baisse -MemoryMB.`n" -ForegroundColor Yellow
}

foreach ($d in 'cache','reports','guest') {
    $p = Join-Path $Root $d
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# --- Construction du .wsb ---------------------------------------------------
$vgpu    = if ($Gpu)     { 'Enable' } else { 'Disable' }
$net     = if ($Network) { 'Default' } else { 'Disable' }
$stealthArg = if ($Stealth) { ' -Stealth' } else { '' }
$cmd     = "powershell.exe -ExecutionPolicy Bypass -NoExit -File C:\BA\kit\Guest-Bootstrap.ps1 -TargetName `"$Target`"$stealthArg"

$wsb = @"
<Configuration>
  <VGpu>$vgpu</VGpu>
  <Networking>$net</Networking>
  <MemoryInMB>$MemoryMB</MemoryInMB>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <PrinterRedirection>Disable</PrinterRedirection>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$Root\guest</HostFolder>
      <SandboxFolder>C:\BA\kit</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$Root\cache</HostFolder>
      <SandboxFolder>C:\BA\cache</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$Root\quarantine</HostFolder>
      <SandboxFolder>C:\BA\in</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$Root\reports</HostFolder>
      <SandboxFolder>C:\BA\out</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>$cmd</Command>
  </LogonCommand>
</Configuration>
"@

$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$safe    = ($Target -replace '[^\w\.-]', '_')
$wsbPath = Join-Path $Root "runs\$safe-$stamp.wsb"
New-Item -ItemType Directory -Path (Split-Path $wsbPath) -Force | Out-Null
$wsb | Set-Content -Path $wsbPath -Encoding UTF8

Write-Host ""
Write-Host "=== Sandbox preparee ===" -ForegroundColor Cyan
Write-Host "  Cible      : $Target"
Write-Host "  Reseau     : $(if ($Network) {'ACTIF  <- le programme peut sortir sur Internet'} else {'COUPE'})" `
    -ForegroundColor $(if ($Network) {'Yellow'} else {'Green'})
Write-Host "  vGPU       : $(if ($Gpu) {'ACTIF'} else {'desactive'})"
Write-Host "  Mode furtif: $(if ($Stealth) {'ACTIF  <- camouflage partiel de la VM'} else {'desactive'})" `
    -ForegroundColor $(if ($Stealth) {'Yellow'} else {'Gray'})
Write-Host "  RAM        : $MemoryMB Mo"
Write-Host "  Config     : $wsbPath"
Write-Host ""
Write-Host "  Ce qui est ATTEIGNABLE depuis la sandbox :" -ForegroundColor Gray
Write-Host "    - le dossier reports\  (ecriture)" -ForegroundColor Gray
Write-Host "    - guest\ cache\ quarantine\  (lecture seule)" -ForegroundColor Gray
Write-Host "  Le reste de C:\ , tes cles SSH, ton profil navigateur : INVISIBLES." -ForegroundColor Green
Write-Host ""

if ($NoLaunch) { Write-Host "Lancement ignore (-NoLaunch). Double-clique le .wsb quand tu veux.`n"; return }

Write-Host "[..] Demarrage de Windows Sandbox..." -ForegroundColor Gray
Start-Process -FilePath $sandboxExe -ArgumentList "`"$wsbPath`""
Write-Host "[ok] La sandbox s'ouvre. Suis les instructions dans la fenetre PowerShell a l'interieur.`n" -ForegroundColor Green
