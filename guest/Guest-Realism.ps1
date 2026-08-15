<#
    BlankAnalyser - couche de "realisme" (option -Stealth).

    But : reduire les signaux triviaux qui disent "tu es dans un bac a sable
    jetable tout neuf". PAS de rendre la VM indetectable -- c'est impossible,
    voir docs/ANTI-VM.md. On vise le malware paresseux qui abandonne au premier
    indice facile, pas l'echantillon cible qui teste le materiel.

    Tout ce qui est fait ici est cosmetique et reversible a la destruction de
    la sandbox. Rien ne touche l'hote.

    A executer AVANT de lancer la cible. Appele par Guest-Bootstrap.ps1 -Stealth.
#>
[CmdletBinding()]
param([int]$AgeDays = 217)

$ErrorActionPreference = 'Continue'
function Ok($m)   { Write-Host "    [realisme] $m" -ForegroundColor DarkGray }
function Warn($m) { Write-Host "    [realisme] $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# 1. Faux historique d'usage : une session neuve n'a ni fichiers recents, ni
#    historique de navigateur, ni documents. Beaucoup de guetteurs comptent
#    juste "combien de fichiers dans Recent / Downloads / Documents".
# ---------------------------------------------------------------------------
try {
    $recent  = [Environment]::GetFolderPath('Recent')
    $docs     = [Environment]::GetFolderPath('MyDocuments')
    $pics     = [Environment]::GetFolderPath('MyPictures')
    $desktop  = [Environment]::GetFolderPath('Desktop')
    $dl       = Join-Path $env:USERPROFILE 'Downloads'

    $names = @(
        'notes','budget_2026','CV','photo_famille','rapport_final','liste_courses',
        'vacances','projet','facture_juin','presentation','devis','sauvegarde_perso',
        'contrat','releve','memo','planning','todo','recette','impots','lettre'
    )
    $exts  = @('.txt','.docx','.pdf','.xlsx','.jpg','.png')

    foreach ($dir in @($docs, $pics, $desktop, $dl)) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $count = 6 + ($names.Count % 5)
        for ($i = 0; $i -lt $count; $i++) {
            $nm = $names[($i * 7 + $dir.Length) % $names.Count]
            $ex = $exts[($i * 3 + $dir.Length) % $exts.Count]
            $fp = Join-Path $dir "$nm$ex"
            if (Test-Path $fp) { $fp = Join-Path $dir "$nm`_$i$ex" }
            $filler = ('x' * (500 + ($i * 137) % 40000))
            Set-Content -Path $fp -Value $filler -Encoding UTF8 -ErrorAction SilentlyContinue
            # backdater : le fichier semble vieux de plusieurs mois
            $past = (Get-Date).AddDays(-($AgeDays - ($i * 4))).AddHours(-($i * 3))
            try {
                $f = Get-Item $fp
                $f.CreationTime   = $past
                $f.LastWriteTime  = $past.AddHours(2)
                $f.LastAccessTime = (Get-Date).AddDays(-($i % 14))
            } catch { }
        }
    }
    Ok "Faux documents et historique d'usage crees et anti-dates."
} catch { Warn "Historique factice partiel : $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
# 2. Bruit de processus : une VRAIE session a des dizaines de processus
#    utilisateur. Ici on lance quelques processus benins et durables pour
#    epaissir la liste (certains malwares comptent les processus, ou cherchent
#    l'absence de navigateur / suite bureautique).
# ---------------------------------------------------------------------------
try {
    # notepad invisible, juste pour exister dans la liste des processus
    1..2 | ForEach-Object {
        Start-Process notepad -WindowStyle Minimized -ErrorAction SilentlyContinue
    }
    Start-Process explorer -ArgumentList ([Environment]::GetFolderPath('MyDocuments')) -ErrorAction SilentlyContinue
    Ok "Processus utilisateur d'ambiance lances."
} catch { }

# ---------------------------------------------------------------------------
# 3. Signaux de temps de fonctionnement / interaction : certains echantillons
#    verifient l'uptime (une VM d'analyse vient de booter) ou l'absence de
#    mouvements souris. On ne peut pas trafiquer l'uptime sans droits noyau,
#    mais on peut simuler de l'activite souris/clavier douce en tache de fond.
# ---------------------------------------------------------------------------
try {
    # Tache de fond detachee : de petits mouvements de souris pendant ~30 min.
    # Volontairement discrets pour ne pas gener quand tu joues vraiment.
    Start-Job -Name BA_Presence -ScriptBlock {
        Add-Type -AssemblyName System.Windows.Forms
        for ($i = 0; $i -lt 600; $i++) {   # ~30 min a 3s d'intervalle
            $p  = [System.Windows.Forms.Cursor]::Position
            $dx = (($i * 17) % 40) - 20
            $dy = (($i * 13) % 40) - 20
            [System.Windows.Forms.Cursor]::Position = `
                New-Object System.Drawing.Point(($p.X + $dx), ($p.Y + $dy))
            Start-Sleep -Seconds 3
        }
    } | Out-Null
    Ok "Activite souris simulee en tache de fond (~30 min)."
} catch { Warn "Simulation d'activite indisponible : $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
# 4. Renommage cosmetique de surface : le nom de la machine et de l'utilisateur.
#    NB : le nom de machine ne changera vraiment qu'apres reboot, ce qu'on ne
#    fait pas ici -- on documente donc que c'est de portee limitee. On peut
#    surtout eviter des noms trop evidents cote variables d'environnement.
# ---------------------------------------------------------------------------
Ok "Note : le nom d'hote et le materiel restent ceux du bac a sable (voir ANTI-VM.md)."

Write-Host "    [realisme] Couche de camouflage appliquee (partielle par conception)." -ForegroundColor Gray
