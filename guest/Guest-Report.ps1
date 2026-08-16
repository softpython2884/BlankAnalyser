<#
    BlankAnalyser - generateur de rapport comportemental.

    Transforme le journal Sysmon (ou le journal de secours) en un rapport
    Markdown court et lisible : ce que le programme a REELLEMENT fait,
    trie par gravite, avec un verdict.

    C'est la reponse au probleme "Procmon me sort 400 000 lignes".
#>
[CmdletBinding()]
param(
    [switch]$KeepRunning,
    # Surchargeables pour tester le generateur hors sandbox
    [string]$WorkRoot = 'C:\Work',
    [string]$OutRoot  = 'C:\BA\out',
    # Crochets de test uniquement : injecter des evenements deja construits
    [object[]]$TestEvents,
    [string]$TestMode
)

$ErrorActionPreference = 'Continue'
$Work = $WorkRoot
$Out  = $OutRoot

# --- Session ----------------------------------------------------------------
$session = $null
if (Test-Path "$Work\_session.json") { $session = Get-Content "$Work\_session.json" -Raw | ConvertFrom-Json }
$start   = if ($session) { [datetime]$session.Start } else { (Get-Date).AddHours(-2) }
$target  = if ($session) { $session.Target } else { '(inconnu)' }
$workDir = if ($session -and $session.WorkDir) { $session.WorkDir } else { "$Work\target" }

Write-Host "`n[..] Collecte des evenements depuis $start ..." -ForegroundColor Cyan

# --- Chargement des evenements ---------------------------------------------
$ev = @()
$mode = 'aucun'

if ($TestEvents) {
    $ev = @($TestEvents); $mode = $TestMode
}
else {
    try {
        $raw = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Sysmon/Operational'; StartTime = $start
        } -ErrorAction Stop
        $mode = 'sysmon'
        foreach ($e in $raw) {
            $d = @{}
            try { ([xml]$e.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' } } catch { }
            $ev += [PSCustomObject]@{ Id = $e.Id; Time = $e.TimeCreated; D = $d }
        }
    } catch {
        if (Test-Path "$Work\_fallback.jsonl") {
            $mode = 'fallback'
            $ev = @(Get-Content "$Work\_fallback.jsonl" | Where-Object { $_ -match '^\{' } |
                    ForEach-Object { try { $_ | ConvertFrom-Json } catch { } })
        }
    }
}

if ($mode -eq 'aucun') {
    Write-Host "[!] Aucun journal exploitable. La surveillance n'a pas demarre." -ForegroundColor Red
    return
}
Write-Host "[ok] $(@($ev).Count) evenement(s), source : $mode" -ForegroundColor Green

# ---------------------------------------------------------------------------
#  Filtrage du bruit
#
#  ATTENTION : ne JAMAIS filtrer sur "c'est dans C:\Windows\System32". Les
#  binaires les plus interessants (powershell, cmd, rundll32, vssadmin...)
#  vivent precisement la. Un filtre par chemin les fait disparaitre du rapport
#  alors que ce sont eux le signal.
#
#  Regle : on ne filtre que si le binaire est A LA FOIS sous C:\Windows\ ET
#  dans la liste nommee des processus de fond bruyants ET pas un LOLBin.
# ---------------------------------------------------------------------------
$LOLBIN   = '(?i)\\(powershell|pwsh|cmd|wscript|cscript|mshta|rundll32|regsvr32|certutil|bitsadmin|curl|wget|msiexec|schtasks|reg|net1?|wmic|at|InstallUtil|Msbuild|odbcconf|cmstp|forfiles|pcalua)\.exe$'
$DESTRUCT = '(?i)\\(vssadmin|wbadmin|bcdedit|cipher|format|diskpart|fsutil|takeown|icacls)\.exe$'
$NOISE    = '(?i)\\(MpCmdRun|MsMpEng|NisSrv|SecurityHealthService|SecurityHealthSystray|SearchIndexer|SearchApp|SearchProtocolHost|SearchFilterHost|Sysmon64|Sysmon|conhost|dllhost|sihost|RuntimeBroker|ctfmon|taskhostw|StartMenuExperienceHost|ShellExperienceHost|backgroundTaskHost|ApplicationFrameHost|smartscreen|fontdrvhost|dwm|csrss|wininit|winlogon|services|lsass|svchost|spoolsv|WmiPrvSE|TrustedInstaller|TiWorker|audiodg|LogonUI|WUDFHost|SgrmBroker|dasHost|UserOOBEBroker|explorer)\.exe$'

function Test-Noise([string]$img) {
    if ([string]::IsNullOrWhiteSpace($img)) { return $false }
    if ($img -match $LOLBIN -or $img -match $DESTRUCT) { return $false }   # jamais masques
    return ($img -match '(?i)^[A-Z]:\\Windows\\' -and $img -match $NOISE)
}

# ---------------------------------------------------------------------------
#  Filtrage du HARNAIS (nos propres outils)
#
#  CRUCIAL : sans ca, le rapport s'accuse lui-meme. Le bootstrap est du
#  PowerShell lance en "-ExecutionPolicy Bypass", RAPPORT.cmd est du cmd.exe,
#  l'installation de Sysmon ecrit dans ...\Services\SysmonDrv. Tout ca
#  ressemble a du malware si on ne l'exclut pas. On identifie nos outils par
#  leurs chemins, noms de scripts, et le binaire Sysmon (renomme ou non).
# ---------------------------------------------------------------------------
$hp = @(
    'C:\\BA\\kit\\', 'C:\\BA\\out\\', 'C:\\BA\\cache\\', 'C:\\BA\\in\\',
    'Guest-Bootstrap', 'Guest-Report', 'Guest-Realism', 'Guest-FallbackMonitor',
    'RAPPORT\.cmd', '-accepteula', 'SysmonDrv', 'BA_Presence', 'BA_FS_', 'BA_Proc',
    '_session\.json', '_fallback\.jsonl'
)
if ($session -and $session.SysmonBin) {
    $leaf = Split-Path ([string]$session.SysmonBin) -Leaf
    if ($leaf) { $hp += [regex]::Escape($leaf) }        # ex. WinHostSvc.exe / Sysmon64.exe
}
$HARNESS = '(?i)(' + ($hp -join '|') + ')'
function Test-Harness([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    return ($s -match $HARNESS)
}

# --- Accumulateurs ----------------------------------------------------------
#  NB : la variable du corps NE DOIT PAS s'appeler $R : PowerShell est
#  insensible a la casse, donc $R et le $r d'une boucle seraient la MEME
#  variable. C'est ce qui faisait planter le rapport en mode Sysmon reel.
$Body  = New-Object System.Collections.Generic.List[string]
$flags = New-Object System.Collections.Generic.List[object]
function Add-Flag($sev, $title, $detail) { $flags.Add([PSCustomObject]@{ Sev = $sev; Title = $title; Detail = $detail }) | Out-Null }
function W($t) { $Body.Add([string]$t) | Out-Null }
function N($x) {                          # comptage robuste : null -> 0, objet -> 1, collection -> count
    if ($null -eq $x) { return 0 }        # Where-Object sans match renvoie $null, pas un tableau vide :
    return @($x).Count                    # sans ce garde, @($null).Count vaudrait 1 (faux positif de verdict)
}

# ===========================================================================
if ($mode -eq 'sysmon') {

    $get = { param($e, $k) if ($e.D.ContainsKey($k)) { $e.D[$k] } else { $null } }

    # Un evenement est ignore s'il vient du bruit systeme OU de notre harnais.
    function Skip-Sys($e) {
        $d = $e.D
        $img  = if ($d.ContainsKey('Image'))       { [string]$d['Image'] }       else { '' }
        $simg = if ($d.ContainsKey('SourceImage')) { [string]$d['SourceImage'] } else { '' }
        if ((Test-Noise $img) -or (Test-Noise $simg)) { return $true }
        $blob = $img + "`n" + $simg
        foreach ($k in 'CommandLine','ParentCommandLine','ParentImage','TargetObject',
                       'TargetFilename','Details','ImageLoaded','TargetImage') {
            if ($d.ContainsKey($k)) { $blob += "`n" + [string]$d[$k] }
        }
        return (Test-Harness $blob)
    }

    # -----------------------------------------------------------------------
    #  ATTRIBUTION A LA CIBLE  (le coeur de la fiabilite du rapport)
    #
    #  Une Sandbox fraiche genere des CENTAINES d'evenements de demarrage
    #  Windows sans aucun rapport avec le jeu. Tenter de tous les lister comme
    #  "bruit" est une bataille perdue -- il en restera toujours un qui passe
    #  et devient un faux "CRITIQUE". A la place, on ne garde QUE l'arbre de
    #  processus du jeu : les processus lances depuis son dossier + toute leur
    #  descendance, identifies par le ProcessGuid unique de Sysmon. Tout le
    #  reste (OS, harnais) tombe de lui-meme.
    # -----------------------------------------------------------------------
    $proc1 = @($ev | Where-Object Id -eq 1)
    $targetGuids = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($e in $proc1) {
        if (([string](& $get $e 'Image')) -like "$workDir*") {
            [void]$targetGuids.Add([string](& $get $e 'ProcessGuid'))
        }
    }
    $changed = $true
    while ($changed) {                        # fermeture transitive : les enfants
        $changed = $false
        foreach ($e in $proc1) {
            $pg  = [string](& $get $e 'ProcessGuid')
            $ppg = [string](& $get $e 'ParentProcessGuid')
            if ($ppg -and $targetGuids.Contains($ppg) -and -not $targetGuids.Contains($pg)) {
                [void]$targetGuids.Add($pg); $changed = $true
            }
        }
    }
    $targetRan = ($targetGuids.Count -gt 0)

    # Un evenement ne "compte" que s'il est attribuable a l'arbre du jeu.
    function InTree($e) {
        $pg = [string](& $get $e 'ProcessGuid')
        if ($pg -and $targetGuids.Contains($pg)) { return $true }
        $spg = [string](& $get $e 'SourceProcessGuid')   # CreateRemoteThread / ProcessAccess
        if ($spg -and $targetGuids.Contains($spg)) { return $true }
        return $false
    }

    # --- 1 : processus ------------------------------------------------------
    $procs = @($proc1 | Where-Object { InTree $_ })
    W "## Processus lances"
    W ""
    if (-not $procs) { W "_Aucun processus notable en dehors du bruit systeme Windows._" }
    else {
        W "| Heure | Processus | Ligne de commande | Parent |"
        W "|---|---|---|---|"
        foreach ($p in $procs) {
            $img = & $get $p 'Image'; $cl = & $get $p 'CommandLine'; $par = & $get $p 'ParentImage'
            $clShort = if ($cl -and $cl.Length -gt 110) { $cl.Substring(0,110) + '...' } else { $cl }
            W "| $($p.Time.ToString('HH:mm:ss')) | ``$(Split-Path $img -Leaf)`` | ``$clShort`` | $(if ($par) { Split-Path $par -Leaf }) |"

            if ($img -match $DESTRUCT) {
                Add-Flag 'CRITIQUE' "Outil de destruction de donnees invoque : $(Split-Path $img -Leaf)" `
                    "Ligne de commande : ``$cl``$([char]10)$([char]10)Suppression de sauvegardes / effacement de volume : signature de rancongiciel ou de wiper. Un jeu ne fait jamais ca."
            }
            elseif ($img -match $LOLBIN) {
                Add-Flag 'HAUTE' "Binaire systeme detourne (LOLBin) : $(Split-Path $img -Leaf)" `
                    "Ligne de commande : ``$cl``$([char]10)$([char]10)Un jeu n'a normalement aucune raison d'appeler un interpreteur de commandes ou un telechargeur systeme."
            }
            # NB : "bypass" seul n'est PAS ici -- "-ExecutionPolicy Bypass" est
            # utilise par des tonnes d'installeurs legitimes (et par notre propre
            # harnais). On ne garde que les signaux forts.
            if ($cl -match '(?i)-enc\s|-e[nc]*\s+[A-Za-z0-9+/]{40}|encodedcommand|frombase64string|-w\s+hidden|-windowstyle\s+hidden|iex\s|invoke-expression|downloadstring|downloadfile|hidden\s+-enc') {
                Add-Flag 'CRITIQUE' "Commande obfusquee ou telechargeante" "``$cl``"
            }
        }
    }
    W ""

    # --- 22 / 3 : reseau ----------------------------------------------------
    $dns = @($ev | Where-Object Id -eq 22 | Where-Object { InTree $_ })
    $net = @($ev | Where-Object Id -eq 3  | Where-Object { InTree $_ })
    W "## Reseau"
    W ""
    if (-not $dns -and -not $net) { W "_Aucune activite reseau observee._"; W "" }
    if ($dns) {
        W "### Domaines interroges (DNS)"
        W ""
        W "| Domaine | Processus | Reponse |"
        W "|---|---|---|"
        $names = @()
        $dns | Group-Object { $_.D['QueryName'] } | ForEach-Object {
            $f = $_.Group[0]; $names += $_.Name
            $ans = & $get $f 'QueryResults'
            if ($ans -and $ans.Length -gt 60) { $ans = $ans.Substring(0,60) + '...' }
            W "| ``$($_.Name)`` | $(Split-Path (& $get $f 'Image') -Leaf) | $ans |"
        }
        W ""
        Add-Flag 'MOYENNE' "$(N $dns) requete(s) DNS sortante(s)" `
            "Domaines : $(($names | Select-Object -First 8) -join ', ').$([char]10)$([char]10)Verifie que ca correspond a une fonction annoncee du jeu (classement, mise a jour). Sinon c'est de l'exfiltration ou du canal de commande."
    }
    if ($net) {
        W "### Connexions etablies"
        W ""
        W "| Processus | Destination | Port |"
        W "|---|---|---|"
        $net | Group-Object { "$($_.D['Image'])|$($_.D['DestinationIp'])|$($_.D['DestinationPort'])" } | ForEach-Object {
            $f = $_.Group[0]
            W "| $(Split-Path (& $get $f 'Image') -Leaf) | $(& $get $f 'DestinationIp') $(& $get $f 'DestinationHostname') | $(& $get $f 'DestinationPort') |"
        }
        W ""
    }

    # --- 9 : acces disque brut ----------------------------------------------
    $raw9 = @($ev | Where-Object Id -eq 9 | Where-Object { InTree $_ })
    if ($raw9) {
        W "## Acces disque brut"
        W ""
        W "| Processus | Peripherique |"
        W "|---|---|"
        $raw9 | Group-Object { "$($_.D['Image'])|$($_.D['Device'])" } | ForEach-Object {
            $f = $_.Group[0]
            W "| ``$(& $get $f 'Image')`` | $(& $get $f 'Device') |"
        }
        W ""
        Add-Flag 'CRITIQUE' "Acces direct au peripherique disque ($(N $raw9) evenements)" `
            "Le programme lit/ecrit le disque en contournant le systeme de fichiers. C'est exactement ce que fait un wiper qui detruit une partition, ou un bootkit qui ecrit le secteur d'amorcage. Aucun jeu legitime ne fait ca."
    }

    # --- 11 / 26 : fichiers --------------------------------------------------
    $created = @($ev | Where-Object Id -eq 11 | Where-Object { InTree $_ })
    $outside = @($created | Where-Object {
        $t = & $get $_ 'TargetFilename'
        $t -and $t -notlike "$workDir*" -and $t -notmatch '(?i)\\Temp\\|\\AppData\\Local\\Temp\\'
    })
    $deleted = @($ev | Where-Object Id -eq 26 | Where-Object { InTree $_ })

    W "## Fichiers"
    W ""
    W "- Crees au total (hors bruit systeme) : **$(N $created)**"
    W "- Crees **hors du dossier du jeu et hors Temp** : **$(N $outside)**"
    W "- Supprimes : **$(N $deleted)**"
    W ""
    if ($outside) {
        W "### Ecritures hors perimetre"
        W ""
        W "| Chemin | Par |"
        W "|---|---|"
        $outside | Select-Object -First 40 | ForEach-Object {
            W "| ``$(& $get $_ 'TargetFilename')`` | $(Split-Path (& $get $_ 'Image') -Leaf) |"
        }
        if ((N $outside) -gt 40) { W "| _... et $((N $outside) - 40) autres_ | |" }
        W ""

        $startup = @($outside | Where-Object { (& $get $_ 'TargetFilename') -match '(?i)\\Start Menu\\Programs\\Startup\\|\\Windows\\System32\\Tasks\\' })
        if ($startup) {
            Add-Flag 'CRITIQUE' "Persistance par dossier de demarrage / tache planifiee" `
                (($startup | ForEach-Object { '`' + (& $get $_ 'TargetFilename') + '`' }) -join ', ')
        }
        Add-Flag 'MOYENNE' "$(N $outside) fichier(s) ecrit(s) hors du dossier du jeu" `
            "Des sauvegardes dans Documents ou AppData sont normales. Des ecritures dans Program Files, dans C:\Windows\ ou sur le Bureau le sont beaucoup moins."
    }
    if ((N $deleted) -gt 50) {
        Add-Flag 'CRITIQUE' "Suppression massive de fichiers ($(N $deleted))" `
            "Exemples : $(($deleted | Select-Object -First 5 | ForEach-Object { '`' + (& $get $_ 'TargetFilename') + '`' }) -join ', ')"
    }

    # --- 12/13/14 : registre -------------------------------------------------
    $reg = @($ev | Where-Object { $_.Id -in 12,13,14 } | Where-Object { InTree $_ })
    if ($reg) {
        W "## Registre - cles sensibles touchees"
        W ""
        W "| Cle | Valeur | Par |"
        W "|---|---|---|"
        foreach ($rev in ($reg | Select-Object -First 30)) {
            $det = & $get $rev 'Details'
            if ($det -and $det.Length -gt 70) { $det = $det.Substring(0,70) + '...' }
            W "| ``$(& $get $rev 'TargetObject')`` | $det | $(Split-Path (& $get $rev 'Image') -Leaf) |"
        }
        W ""
        $persist = @($reg | Where-Object { (& $get $_ 'TargetObject') -match '(?i)\\CurrentVersion\\Run|\\Winlogon|Image File Execution Options|\\Services\\' })
        if ($persist) {
            Add-Flag 'CRITIQUE' "Persistance installee dans le registre" `
                "Le programme s'inscrit pour redemarrer automatiquement : $(($persist | Select-Object -First 4 | ForEach-Object { '`' + (& $get $_ 'TargetObject') + '`' }) -join ', ')"
        }
        if (@($reg | Where-Object { (& $get $_ 'TargetObject') -match '(?i)Windows Defender' })) {
            Add-Flag 'CRITIQUE' "Tentative de modification de Windows Defender" "Desactivation de l'antivirus."
        }
    }

    # --- 6 / 8 / 10 / 24 / 25 : bas niveau ----------------------------------
    # Event 6 (DriverLoad) n'a PAS de ProcessGuid : on ne peut pas l'attribuer a
    # l'arbre du jeu. On se rabat sur l'exclusion du harnais (SysmonDrv).
    $drv   = @($ev | Where-Object Id -eq 6  | Where-Object { -not (Skip-Sys $_) })
    $crt   = @($ev | Where-Object Id -eq 8  | Where-Object { InTree $_ })
    $lsass = @($ev | Where-Object { $_.Id -eq 10 -and (& $get $_ 'TargetImage') -match '(?i)lsass\.exe' } | Where-Object { InTree $_ })
    $tamp  = @($ev | Where-Object Id -eq 25 | Where-Object { InTree $_ })
    $clip  = @($ev | Where-Object Id -eq 24 | Where-Object { InTree $_ })

    if ($drv)   { Add-Flag 'CRITIQUE' "Chargement de driver noyau ($(N $drv))" (($drv | ForEach-Object { '`' + (& $get $_ 'ImageLoaded') + '`' }) -join ', ') }
    if ($crt)   { Add-Flag 'CRITIQUE' "Injection de code dans un autre processus ($(N $crt))" "Source : $(($crt | ForEach-Object { Split-Path (& $get $_ 'SourceImage') -Leaf } | Select-Object -Unique) -join ', ')" }
    if ($lsass) { Add-Flag 'CRITIQUE' "Acces a lsass.exe ($(N $lsass))" "Signature du vol d'identifiants Windows." }
    if ($tamp)  { Add-Flag 'CRITIQUE' "Process hollowing / tampering ($(N $tamp))" "Le programme remplace le code d'un processus legitime pour s'y cacher." }
    if ($clip)  { Add-Flag 'HAUTE' "Lecture du presse-papier ($(N $clip))" "Technique du 'clipper' : remplace une adresse de portefeuille copiee. A rapprocher de l'usage reel du jeu." }

    if ($drv -or $crt -or $lsass -or $tamp -or $clip) {
        W "## Manipulations de bas niveau"
        W ""
        if ($drv)   { W "- Drivers charges : $(($drv | ForEach-Object { & $get $_ 'ImageLoaded' }) -join ', ')" }
        if ($crt)   { W "- Injections de thread distant : $(N $crt)" }
        if ($lsass) { W "- Acces a lsass.exe : $(N $lsass)" }
        if ($tamp)  { W "- Process tampering : $(N $tamp)" }
        if ($clip)  { W "- Lectures du presse-papier : $(N $clip)" }
        W ""
    }
}
# ===========================================================================
else {
    # --- Mode de secours ----------------------------------------------------
    W "> **Mode degrade** : Sysmon n'a pas pu charger son driver. Les acces disque"
    W "> brut, les injections de code et les evenements de registre ne sont PAS"
    W "> couverts par ce rapport."
    W ""

    $targetRan = [bool]@($ev | Where-Object type -eq 'process' |
        Where-Object { ([string]$_.image) -like "$workDir*" }).Count

    $p = @($ev | Where-Object type -eq 'process' |
        Where-Object { -not (Test-Noise $_.image) -and -not (Test-Harness "$($_.image) $($_.commandline)") })
    $f = @($ev | Where-Object type -eq 'file'    | Where-Object { -not (Test-Harness ([string]$_.path)) })
    $n = @($ev | Where-Object type -eq 'network' | Where-Object { -not (Test-Harness "$($_.process) $($_.image)") })

    W "## Processus lances"
    W ""
    if (-not $p) { W "_Aucun processus notable._"; W "" }
    else {
        W "| Heure | Processus | Ligne de commande |"
        W "|---|---|---|"
        foreach ($x in $p) {
            $cl = $x.commandline
            $clShort = if ($cl -and $cl.Length -gt 110) { $cl.Substring(0,110) + '...' } else { $cl }
            W "| $(([datetime]$x.t).ToString('HH:mm:ss')) | ``$($x.name)`` | ``$clShort`` |"
            if ($x.image -match $DESTRUCT) {
                Add-Flag 'CRITIQUE' "Outil de destruction de donnees invoque : $($x.name)" `
                    "Ligne de commande : ``$cl``$([char]10)$([char]10)Suppression de sauvegardes / effacement de volume : signature de rancongiciel ou de wiper."
            }
            elseif ($x.image -match $LOLBIN) {
                Add-Flag 'HAUTE' "Binaire systeme detourne (LOLBin) : $($x.name)" "Ligne de commande : ``$cl``"
            }
            if ($cl -match '(?i)-enc\s|encodedcommand|frombase64string|-w\s+hidden|-windowstyle\s+hidden|iex\s|invoke-expression|downloadstring|downloadfile') {
                Add-Flag 'CRITIQUE' "Commande obfusquee ou telechargeante" "``$cl``"
            }
        }
        W ""
    }

    W "## Reseau"
    W ""
    if (-not $n) { W "_Aucune connexion sortante._"; W "" }
    else {
        W "| Processus | Destination | Port |"
        W "|---|---|---|"
        $n | ForEach-Object { W "| $($_.process) | $($_.remote) | $($_.port) |" }
        W ""
        Add-Flag 'MOYENNE' "$(N $n) connexion(s) sortante(s)" `
            "Vers : $(($n | Select-Object -ExpandProperty remote -Unique) -join ', ')"
    }

    $outside = @($f | Where-Object { $_.path -notlike "$workDir*" -and $_.path -notmatch '(?i)\\Temp\\' })
    W "## Fichiers"
    W ""
    W "- Evenements fichiers : **$(N $f)** (dont **$(N $outside)** hors du dossier du jeu)"
    W ""
    if ($outside) {
        W "| Operation | Chemin |"
        W "|---|---|"
        $outside | Select-Object -First 40 | ForEach-Object { W "| $($_.op) | ``$($_.path)`` |" }
        if ((N $outside) -gt 40) { W "| _... et $((N $outside) - 40) autres_ | |" }
        W ""
        $del = @($outside | Where-Object op -eq 'Deleted')
        if ((N $del) -gt 50) { Add-Flag 'CRITIQUE' "Suppression massive de fichiers ($(N $del))" "" }
        $su = @($outside | Where-Object { $_.path -match '(?i)\\Startup\\|\\System32\\Tasks\\' })
        if ($su) { Add-Flag 'CRITIQUE' "Persistance par dossier de demarrage / tache planifiee" (($su | ForEach-Object { '`' + $_.path + '`' }) -join ', ') }
        Add-Flag 'MOYENNE' "$(N $outside) fichier(s) touche(s) hors du dossier du jeu" ""
    }
}

# --- Verdict ----------------------------------------------------------------
$order = @{ 'CRITIQUE' = 0; 'HAUTE' = 1; 'MOYENNE' = 2 }
$flagList = @($flags | Sort-Object { $order[$_.Sev] })
$crit = N ($flagList | Where-Object Sev -eq 'CRITIQUE')
$high = N ($flagList | Where-Object Sev -eq 'HAUTE')
$med  = N ($flagList | Where-Object Sev -eq 'MOYENNE')

if ($null -eq $targetRan) { $targetRan = $true }   # securite

$verdict = if (-not $targetRan -and $crit -eq 0 -and $high -eq 0) {
                                        "CIBLE JAMAIS LANCEE - rien a analyser"
           }
           elseif ($crit -gt 0)       { "NE PAS EXECUTER SUR L'HOTE" }
           elseif ($high -gt 0)        { "SUSPECT - a examiner avant tout usage hors sandbox" }
           elseif ($flagList.Count -gt 0) { "RIEN DE DISQUALIFIANT, quelques points a verifier" }
           else                        { "AUCUN COMPORTEMENT SUSPECT OBSERVE" }

# --- Assemblage -------------------------------------------------------------
$head = [System.Collections.Generic.List[string]]::new()
$head.Add("# Rapport comportemental - BlankAnalyser")
$head.Add("")
$head.Add("| | |")
$head.Add("|---|---|")
$head.Add("| **Cible** | ``$target`` |")
$head.Add("| **Debut d'observation** | $start |")
$head.Add("| **Fin** | $(Get-Date) |")
$head.Add("| **Source** | $mode |")
$head.Add("| **Evenements** | $(N $ev) |")
if ($session -and $session.Stealth) { $head.Add("| **Mode furtif** | actif (camouflage partiel - voir limites) |") }
$head.Add("")
$head.Add("> ## VERDICT : $verdict")
$head.Add(">")
$head.Add("> $crit critique(s), $high haute(s), $med moyenne(s).")
$head.Add("")
if (-not $targetRan) {
    $head.Add("> [!] **Aucun processus n'a ete lance depuis le dossier du jeu**")
    $head.Add("> (``$workDir``). Tu as tres probablement genere ce rapport **avant**")
    $head.Add("> de lancer le jeu. Les evenements ci-dessous ne sont donc PAS le jeu :")
    $head.Add("> lance-le, utilise-le quelques minutes, PUIS relance RAPPORT.cmd.")
    $head.Add("")
}

if ($flagList.Count) {
    $head.Add("## Points releves")
    $head.Add("")
    foreach ($fl in $flagList) {
        $icon = switch ($fl.Sev) { 'CRITIQUE' { '[!!!]' } 'HAUTE' { '[!!]' } default { '[!]' } }
        $head.Add("### $icon $($fl.Sev) - $($fl.Title)")
        $head.Add("")
        if ($fl.Detail) { $head.Add([string]$fl.Detail); $head.Add("") }
    }
}
$head.Add("---")
$head.Add("")
$head.Add("# Detail des observations")
$head.Add("")

$footer = @(
    ""
    "---"
    ""
    "### Limites de cette analyse"
    ""
    "- Un malware peut **detecter la sandbox** et rester inerte. Un rapport propre"
    "  apres 3 minutes de jeu ne vaut pas un rapport propre apres 2 heures."
    "- Le **mode furtif** ne fait que ralentir la detection paresseuse : le"
    "  processeur virtualise et le compte WDAGUtilityAccount trahissent toujours"
    "  la VM a un echantillon determine (docs/ANTI-VM.md)."
    "- Beaucoup de charges utiles sont **retardees** (des jours) ou **conditionnelles**"
    "  (date, presence d'un portefeuille crypto, domaine d'entreprise)."
    "- Le mode degrade ne voit ni le registre, ni les acces disque brut."
    "- Ce rapport dit ce qui **s'est passe**, pas ce qui **aurait pu** se passer."
    ""
    "Ce que ca change quand meme : tout ce qui est decrit ici s'est produit dans une"
    "machine jetable. Les cles SSH, le profil navigateur et les disques de l'hote"
    "n'ont jamais ete accessibles."
)

$final = @($head) + @($Body) + @($footer)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$safe  = ($target -replace '[^\w\.-]','_')
$file  = Join-Path $Out "comportement-$safe-$stamp.md"
New-Item -ItemType Directory -Path $Out -Force -ErrorAction SilentlyContinue | Out-Null
$final -join "`r`n" | Set-Content -Path $file -Encoding UTF8

# --- Affichage console ------------------------------------------------------
Write-Host ""
$vc = if ($crit) { 'Red' } elseif ($high) { 'Yellow' } else { 'Green' }
Write-Host "================================================================" -ForegroundColor $vc
Write-Host "  VERDICT : $verdict" -ForegroundColor $vc
Write-Host "================================================================" -ForegroundColor $vc
Write-Host ""
foreach ($fl in $flagList) {
    $c = switch ($fl.Sev) { 'CRITIQUE' { 'Red' } 'HAUTE' { 'Yellow' } default { 'Gray' } }
    Write-Host "  [$($fl.Sev)] $($fl.Title)" -ForegroundColor $c
}
if (-not $flagList.Count) { Write-Host "  Rien a signaler dans ce qui a ete observe." -ForegroundColor Green }
Write-Host ""
if (-not $targetRan) {
    Write-Host "  [!] La cible n'a JAMAIS ete lancee depuis son dossier." -ForegroundColor Yellow
    Write-Host "      Tu as sans doute lance ce rapport AVANT le jeu." -ForegroundColor Yellow
    Write-Host "      -> Lance le jeu, utilise-le, PUIS relance RAPPORT.cmd." -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "  Rapport complet -> $file" -ForegroundColor Cyan
Write-Host "  (= dossier reports\ sur ton PC, il survit a la fermeture de la sandbox)" -ForegroundColor Gray
Write-Host ""

# NE PAS desinstaller l'observateur : la sandbox est jetable, tout disparait a
# la fermeture. Le laisser tourner permet de relancer RAPPORT.cmd autant de fois
# qu'on veut (jouer plus, re-tester...). Le desinstaller cassait le 2e rapport.
if ($mode -eq 'sysmon') {
    Write-Host "  L'observation reste ACTIVE : tu peux jouer encore, puis relancer" -ForegroundColor DarkGray
    Write-Host "  RAPPORT.cmd pour un rapport a jour. (Tout s'efface a la fermeture.)" -ForegroundColor DarkGray
    Write-Host ""
}
