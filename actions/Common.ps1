# Shared helper functions for action scripts.
# Dot-sourced by each action script via: . (Join-Path $PSScriptRoot "Common.ps1")

# ---------------------------
# INI helper
# ---------------------------
function Get-IniValue {
    param(
        [string]$FilePath,
        [string]$Section,
        [string[]]$Key
    )

    $result = @{}
    foreach ($k in $Key) { $result[$k] = $null }

    if (-not (Test-Path $FilePath)) { return $result }

    try {
        $lines = Get-Content -Path $FilePath -ErrorAction Stop
    } catch {
        Write-Warning "Failed to read ini file '$FilePath': $_"
        return $result
    }

    $inTargetSection = $false
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inTargetSection = ($matches[1].Trim() -eq $Section)
            continue
        }
        if ($inTargetSection -and $trimmed -match '^([^=;#]+)\s*=\s*(.*)$') {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()
            if ($Key -contains $k) {
                $result[$k] = $v
            }
        }
    }
    return $result
}

function Get-ActionContext {
    param(
        [string]$ConfigJsonPath,
        [string]$Key
    )

    if (-not (Test-Path $ConfigJsonPath)) {
        throw "Config file not found: $ConfigJsonPath"
    }

    $json = Get-Content $ConfigJsonPath -Raw | ConvertFrom-Json

    $entryJson = $json.Entries | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    if (-not $entryJson) {
        throw "No entry found for Key '$Key' in $ConfigJsonPath"
    }

    $scriptRootForConfig = Split-Path $ConfigJsonPath -Parent
    $configPath = Join-Path $scriptRootForConfig (Join-Path "maps" $entryJson.Key)

    $procName = $json.GlobalSettings.Process.Name
    $procSubPath = $json.GlobalSettings.Process.Path

    $entryPid = $null
    $ramGB = $null
    $startTime = $null

    if (-not [string]::IsNullOrWhiteSpace($procName) -and -not [string]::IsNullOrWhiteSpace($entryJson.ServerPath)) {
        try {
            $filterName = if ($procName -notmatch '\.exe$') { "$procName.exe" } else { $procName }
            $procs = Get-CimInstance Win32_Process -Filter "Name = '$filterName'" -ErrorAction Stop
            $expectedPath = (Join-Path $entryJson.ServerPath $procSubPath).TrimEnd('\').ToLowerInvariant()

            foreach ($proc in $procs) {
                if (-not $proc.ExecutablePath) { continue }
                $procDir = (Split-Path $proc.ExecutablePath -Parent).TrimEnd('\').ToLowerInvariant()
                if ($procDir -eq $expectedPath) {
                    $entryPid = $proc.ProcessId
                    if ($proc.WorkingSetSize) { $ramGB = [math]::Round($proc.WorkingSetSize / 1GB, 2) }
                    if ($proc.CreationDate) { $startTime = $proc.CreationDate }
                    break
                }
            }
        } catch {
            Write-Warning "Failed to query processes: $_"
        }
    }

    return [PSCustomObject]@{
        Key         = $entryJson.Key
        ServerPath  = $entryJson.ServerPath
        ConfigPath  = $configPath
        Pid         = $entryPid
        RamGB       = $ramGB
        StartTime   = $startTime
        ProcessName = $procName
        ProcessPath = $procSubPath
        GlobalSettings = $json.GlobalSettings
        BackupPath   = (Join-Path  $json.GlobalSettings.Backup.Path $entryJson.Key)
    }
}

function Test-ProcessRunning {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Ctx
    )

    if ([string]::IsNullOrWhiteSpace($Ctx.ProcessName) -or [string]::IsNullOrWhiteSpace($Ctx.ServerPath)) {
        return $false
    }

    $procFileName = if ($Ctx.ProcessName -notmatch '\.exe$') { "$($Ctx.ProcessName).exe" } else { $Ctx.ProcessName }
    $exePath = (Join-Path (Join-Path $Ctx.ServerPath $Ctx.ProcessPath) $procFileName).ToLowerInvariant()

    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name = '$procFileName'" -ErrorAction Stop
        foreach ($proc in $procs) {
            if ($proc.ExecutablePath -and $proc.ExecutablePath.ToLowerInvariant() -eq $exePath) {
                return $proc.ProcessId
            }
        }
    } catch {
        Write-Warning "Failed to query processes: $_"
    }

    return $false
}

# ---------------------------
# Cross-process per-Key lock (named Mutex) - prevents concurrent actions on the same server
# ---------------------------
function Enter-ActionLock {
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [int]$TimeoutSeconds = 0
    )

    $mutexName = "Global\ServerManager_Action_$Key"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)

    try {
        $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
    } catch [System.Threading.AbandonedMutexException] {
        # Previous owner was killed/crashed while holding the lock - we now own it
        $acquired = $true
    }

    if (-not $acquired) {
        $mutex.Dispose()
        return $null
    }

    return $mutex
}

function Exit-ActionLock {
    param(
        [System.Threading.Mutex]$Mutex
    )

    if (-not $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch { }
    $Mutex.Dispose()
}
