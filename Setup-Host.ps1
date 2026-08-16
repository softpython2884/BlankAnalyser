<#
.SYNOPSIS
    BlankAnalyser - Preparation de l'hote. A lancer UNE SEULE FOIS, en administrateur.
.DESCRIPTION
    - Active la fonctionnalite Windows Sandbox (Containers-DisposableClientVM)
    - Cree l'arborescence de travail
    - Telecharge Sysmon + Procmon (~10 Mo au total, une seule fois)
    - Telecharge les runtimes Visual C++ x64/x86 (~40 Mo, une seule fois)
#>
[CmdletBinding()]
param(
    [switch]$SkipDownload,
    [switch]$SkipFeature,
    [switch]$SkipRedist    # ne pas telecharger les runtimes Visual C++ (~40 Mo)
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

Say "`n=== BlankAnalyser : preparation de l'hote ===`n" Cyan

# --- 1. Arborescence -------------------------------------------------------
foreach ($d in 'cache\tools', 'cache\redist', 'quarantine', 'reports', 'runs') {
    $p = Join-Path $Root $d
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
Say "[ok] Arborescence creee." Green

# --- 2. Fonctionnalite Windows Sandbox -------------------------------------
if (-not $SkipFeature) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Say "[!] Pas administrateur : impossible d'activer Windows Sandbox." Yellow
        Say "    Relance ce script dans un PowerShell 'Executer en tant qu'administrateur'," Yellow
        Say "    ou lance manuellement :" Yellow
        Say "    Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All`n" White
    }
    elseif (Test-Path "$env:SystemRoot\System32\WindowsSandbox.exe") {
        Say "[ok] Windows Sandbox est deja installe." Green
    }
    else {
        Say "[..] Activation de Windows Sandbox (peut prendre 1-2 min)..." Gray
        $r = Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -All -NoRestart
        Say "[ok] Fonctionnalite activee." Green
        if ($r.RestartNeeded) { Say "[!] REDEMARRAGE REQUIS avant la premiere utilisation." Yellow }
    }
}

# --- 3. Outils d'observation ------------------------------------------------
if (-not $SkipDownload) {
    $tools = @(
        @{ Name = 'Sysmon64.exe';  Url = 'https://live.sysinternals.com/Sysmon64.exe';  Why = 'moniteur comportemental principal' }
        @{ Name = 'Procmon64.exe'; Url = 'https://live.sysinternals.com/Procmon64.exe'; Why = 'analyse fine (optionnel)' }
    )
    foreach ($t in $tools) {
        $dest = Join-Path $Root "cache\tools\$($t.Name)"
        if (Test-Path $dest) { Say "[ok] $($t.Name) deja present." Green; continue }
        Say "[..] Telechargement $($t.Name) ($($t.Why))..." Gray
        try {
            $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $t.Url -OutFile $dest -UseBasicParsing
            $ProgressPreference = $old
            Say "[ok] $($t.Name) -> cache\tools\ ($([math]::Round((Get-Item $dest).Length/1MB,1)) Mo)" Green
        } catch {
            Say "[!] Echec du telechargement de $($t.Name) : $($_.Exception.Message)" Yellow
            Say "    Recupere-le a la main sur https://learn.microsoft.com/sysinternals/downloads/" Yellow
        }
    }
}

# --- 4. Redistribuables Visual C++ (indispensables a la plupart des jeux) ---
#  C'est LA reponse au "VCRUNTIME140.dll introuvable". Telecharge une seule
#  fois ici, puis installe automatiquement dans chaque sandbox depuis le cache.
$redistDir = Join-Path $Root 'cache\redist'
if (-not (Test-Path $redistDir)) { New-Item -ItemType Directory -Path $redistDir -Force | Out-Null }

if (-not $SkipRedist -and -not $SkipDownload) {
    Say "`n--- Runtimes Visual C++ (une seule fois, ~40 Mo) ---" Cyan
    $redists = @(
        @{ Name = 'vc_redist.x64.exe'; Url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'; Size = '~25 Mo' }
        @{ Name = 'vc_redist.x86.exe'; Url = 'https://aka.ms/vs/17/release/vc_redist.x86.exe'; Size = '~14 Mo' }
    )
    foreach ($r in $redists) {
        $dest = Join-Path $redistDir $r.Name
        if (Test-Path $dest) { Say "[ok] $($r.Name) deja present." Green; continue }
        Say "[..] Telechargement $($r.Name) ($($r.Size))..." Gray
        try {
            $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $r.Url -OutFile $dest -UseBasicParsing
            $ProgressPreference = $old
            Say "[ok] $($r.Name) -> cache\redist\ ($([math]::Round((Get-Item $dest).Length/1MB,1)) Mo)" Green
        } catch {
            Say "[!] Echec $($r.Name) : $($_.Exception.Message)" Yellow
            Say "    A recuperer a la main : $($r.Url)" Yellow
        }
    }
}

$redistCount = @(Get-ChildItem $redistDir -File -Filter *.exe -ErrorAction SilentlyContinue).Count
Say "`n--- Cache de dependances : $redistCount runtime(s) dans cache\redist\ ---" Cyan
Say @"
  Ces .exe sont installes automatiquement (/quiet /norestart) dans chaque
  sandbox. Pour un jeu .NET, ajoute aussi dotnet-runtime-*.exe ici.
"@ White

Say "`n=== Termine. Etape suivante : .\Triage-Host.ps1 -Target <ton fichier> ===`n" Cyan
