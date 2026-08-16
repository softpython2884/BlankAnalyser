<#
    BlankAnalyser - visionneuse de fichiers pour la sandbox.

    Windows Sandbox n'a ni Notepad ni editeur : impossible autrement de lire
    un fichier qu'un programme aurait cree (note de rancon, config, log...).
    Cette visionneuse ouvre un selecteur, affiche le texte, et pour un binaire
    montre un apercu hexadecimal + le type detecte -- le tout en LECTURE SEULE.
#>
Add-Type -AssemblyName System.Windows.Forms

$start = 'C:\Work\target'
if (-not (Test-Path $start)) { $start = 'C:\Work' }

function Show-File($path) {
    $fi = Get-Item -LiteralPath $path
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $($fi.FullName)" -ForegroundColor Cyan
    Write-Host "  $([math]::Round($fi.Length/1KB,1)) Ko  -  modifie $($fi.LastWriteTime)" -ForegroundColor DarkGray
    Write-Host ("=" * 70) -ForegroundColor Cyan

    # Lit le debut en octets pour deviner texte vs binaire.
    $bytes = [System.IO.File]::ReadAllBytes($fi.FullName)
    $sample = if ($bytes.Length -gt 8192) { $bytes[0..8191] } else { $bytes }
    $nul = @($sample | Where-Object { $_ -eq 0 }).Count
    $isText = ($sample.Length -eq 0) -or (($nul / [math]::Max($sample.Length,1)) -lt 0.01)

    if ($isText) {
        try {
            $txt = [System.IO.File]::ReadAllText($fi.FullName)
            $lines = $txt -split "`n"
            $max = 500
            if ($lines.Count -gt $max) {
                $lines[0..($max-1)] | ForEach-Object { Write-Host $_ }
                Write-Host "`n  [... $($lines.Count - $max) lignes de plus, fichier tronque a l'affichage ...]" -ForegroundColor Yellow
            } else {
                $lines | ForEach-Object { Write-Host $_ }
            }
        } catch { Write-Host "  Lecture texte impossible : $($_.Exception.Message)" -ForegroundColor Red }
    }
    else {
        Write-Host "  [Fichier binaire] Apercu des 256 premiers octets :" -ForegroundColor Yellow
        Write-Host ""
        $n = [math]::Min(256, $bytes.Length)
        for ($i = 0; $i -lt $n; $i += 16) {
            $chunk = $bytes[$i..([math]::Min($i+15, $n-1))]
            $hex = ($chunk | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            $asc = ($chunk | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } }) -join ''
            Write-Host ("  {0:X4}  {1,-48}  {2}" -f $i, $hex, $asc)
        }
        # Signature de type courante
        $sig = ($bytes[0..([math]::Min(3,$bytes.Length-1))] | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        $type = switch -Regex ($sig) {
            '^4D5A'     { 'Executable Windows (MZ/PE)' ; break }
            '^504B'     { 'Archive ZIP / Office' ; break }
            '^7F454C46' { 'Executable Linux (ELF)' ; break }
            '^25504446' { 'PDF' ; break }
            '^89504E47' { 'Image PNG' ; break }
            default     { 'inconnu' }
        }
        Write-Host ""
        Write-Host "  Type devine : $type" -ForegroundColor Cyan
    }
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

Clear-Host
Write-Host @"
================================================================
  BlankAnalyser - visionneuse de fichiers (lecture seule)
================================================================
  Choisis un fichier a inspecter. Utile pour lire ce qu'un
  programme a cree sans avoir a l'executer.
================================================================
"@ -ForegroundColor Cyan

while ($true) {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.InitialDirectory = $start
    $dlg.Title = 'BlankAnalyser - choisir un fichier a lire'
    $dlg.Filter = 'Tous les fichiers (*.*)|*.*'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { break }

    try { Show-File $dlg.FileName }
    catch { Write-Host "  Erreur : $($_.Exception.Message)" -ForegroundColor Red }

    $start = Split-Path $dlg.FileName -Parent
    Write-Host ""
    $again = Read-Host "  Voir un autre fichier ? (o/N)"
    if ($again -notmatch '^[oOyY]') { break }
}

Write-Host "`n  Fermeture de la visionneuse.`n" -ForegroundColor DarkGray
