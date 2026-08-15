<#
    BlankAnalyser - moniteur de secours.

    Utilise si Sysmon ne peut pas charger son driver. Ne voit pas tout
    (pas d'acces disque brut, pas d'injection de thread), mais couvre les
    trois signaux les plus utiles sans aucun composant noyau :
      - creation de processus (WMI)
      - creation / suppression de fichiers hors zone de travail
      - connexions TCP sortantes

    Ecrit du JSONL dans C:\Work\_fallback.jsonl
#>
$ErrorActionPreference = 'Continue'
$Work = 'C:\Work'
$Log  = Join-Path $Work '_fallback.jsonl'
New-Item -ItemType Directory -Path $Work -Force | Out-Null
'' | Set-Content $Log -Encoding UTF8

$script:sync = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

function Push-Event($type, $data) {
    $o = [ordered]@{ t = (Get-Date).ToString('o'); type = $type }
    foreach ($k in $data.Keys) { $o[$k] = $data[$k] }
    $script:sync.Enqueue(($o | ConvertTo-Json -Compress -Depth 4))
}

# --- Processus --------------------------------------------------------------
try {
    Register-CimIndicationEvent -ClassName Win32_ProcessStartTrace -SourceIdentifier 'BA_Proc' -Action {
        $e = $Event.SourceEventArgs.NewEvent
        $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$($e.ProcessID)" -ErrorAction SilentlyContinue
        $line = [ordered]@{
            t           = (Get-Date).ToString('o')
            type        = 'process'
            name        = $e.ProcessName
            pid         = $e.ProcessID
            ppid        = $e.ParentProcessID
            image       = if ($ci) { $ci.ExecutablePath } else { $null }
            commandline = if ($ci) { $ci.CommandLine } else { $null }
        } | ConvertTo-Json -Compress
        Add-Content -Path 'C:\Work\_fallback.jsonl' -Value $line -Encoding UTF8
    } | Out-Null
} catch { Push-Event 'error' @{ msg = "WMI process trace indisponible: $($_.Exception.Message)" } }

# --- Fichiers ---------------------------------------------------------------
$watchRoots = @('C:\Users', 'C:\ProgramData', 'C:\Windows\System32\Tasks', 'C:\Program Files')
$watchers = @()
foreach ($root in $watchRoots) {
    if (-not (Test-Path $root)) { continue }
    try {
        $w = New-Object System.IO.FileSystemWatcher $root, '*'
        $w.IncludeSubdirectories = $true
        $w.EnableRaisingEvents = $true
        $watchers += $w
        foreach ($evt in 'Created', 'Deleted', 'Renamed') {
            Register-ObjectEvent -InputObject $w -EventName $evt -SourceIdentifier "BA_FS_${root}_$evt" -Action {
                $p = $EventArgs.FullPath
                # bruit systeme sans valeur analytique
                if ($p -match '\\(INetCache|WER|Prefetch|CrashDumps|Temp\\__PSScriptPolicy)\\' -or
                    $p -match '\.(etl|evtx|tmp|log)$') { return }
                ([ordered]@{
                    t    = (Get-Date).ToString('o')
                    type = 'file'
                    op   = $Event.SourceEventArgs.ChangeType.ToString()
                    path = $p
                } | ConvertTo-Json -Compress) | Add-Content -Path 'C:\Work\_fallback.jsonl' -Encoding UTF8
            } | Out-Null
        }
    } catch { }
}

# --- Reseau (echantillonnage) ----------------------------------------------
$seen = @{}
Push-Event 'info' @{ msg = 'moniteur de secours demarre' }
while ($true) {
    $q = $null
    while ($script:sync.TryDequeue([ref]$q)) { Add-Content -Path $Log -Value $q -Encoding UTF8 }

    try {
        Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Where-Object { $_.RemoteAddress -notin '0.0.0.0','127.0.0.1','::','::1' -and $_.State -ne 'Listen' } |
            ForEach-Object {
                $key = "$($_.OwningProcess)|$($_.RemoteAddress)|$($_.RemotePort)"
                if ($seen.ContainsKey($key)) { return }
                $seen[$key] = $true
                $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                ([ordered]@{
                    t       = (Get-Date).ToString('o')
                    type    = 'network'
                    process = if ($proc) { $proc.ProcessName } else { "pid:$($_.OwningProcess)" }
                    image   = if ($proc) { $proc.Path } else { $null }
                    remote  = $_.RemoteAddress
                    port    = $_.RemotePort
                    state   = $_.State.ToString()
                } | ConvertTo-Json -Compress) | Add-Content -Path $Log -Encoding UTF8
            }
    } catch { }

    Start-Sleep -Seconds 3
}
