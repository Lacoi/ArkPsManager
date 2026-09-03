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
    $configPath = Join-Path $scriptRootForConfig (Join-Path "config/maps" $entryJson.Key)

    $procName = $json.GlobalSettings.Process.Name
    $procSubPath = $json.GlobalSettings.Process.Path

    $entryPid = $null
    $ramGB = $null
    $startTime = $null

    if (-not [string]::IsNullOrWhiteSpace($procName) -and -not [string]::IsNullOrWhiteSpace($entryJson.ServerPath)) {
        try {
            $baseName = $procName -replace '\.exe$', ''
            $procs = Get-Process -Name $baseName -ErrorAction SilentlyContinue
            $expectedPath = (Join-Path $entryJson.ServerPath $procSubPath).TrimEnd('\').ToLowerInvariant()

            foreach ($proc in $procs) {
                $exePath = $null
                try { $exePath = $proc.Path } catch { continue }
                if (-not $exePath) { continue }
                $procDir = (Split-Path $exePath -Parent).TrimEnd('\').ToLowerInvariant()
                if ($procDir -eq $expectedPath) {
                    $entryPid = $proc.Id
                    $ramGB = [math]::Round($proc.WorkingSet64 / 1GB, 2)
                    try { $startTime = $proc.StartTime } catch { }
                    break
                }
            }
            # Process objects hold native handles - dispose now that values have been copied out
            foreach ($proc in $procs) { 
                try { $proc.Dispose() } catch { } 
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
        UseLatestBuild = [bool]$entryJson.UseLatestBuild
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

    $baseName = $Ctx.ProcessName -replace '\.exe$', ''
    $exePath = (Join-Path (Join-Path $Ctx.ServerPath $Ctx.ProcessPath) $baseName).ToLowerInvariant()

    try {
        $procs = Get-Process -Name $baseName -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            $procPath = $null
            try { $procPath = $proc.Path } catch { continue }
            if ($procPath -and $procPath.ToLowerInvariant() -eq $exePath) {
                $result = $proc.Id
                try { $proc.Dispose() } catch { }
                return $result
            }
        }
        foreach ($proc in $procs) { 
            try { $proc.Dispose() } catch { } 
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

function Get-ActionLogPath {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Ctx,
        [Parameter(Mandatory)][string]$ActionName
    )

    $logDir = Join-Path (Join-Path (Get-Item $PSScriptRoot ).Parent.FullName "logs") $Ctx.Key

    # Only hit the filesystem once per directory per process run
    if (-not $script:EnsuredLogDirs) { $script:EnsuredLogDirs = @{} }
    if (-not $script:EnsuredLogDirs.ContainsKey($logDir)) {
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $script:EnsuredLogDirs[$logDir] = $true
    }

    return Join-Path $logDir "$ActionName.log"
}

function Write-ActionLog {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Message
    )

    Write-Host $Message

    $parent = Split-Path $LogPath -Parent
    if (-not $script:EnsuredLogDirs) { $script:EnsuredLogDirs = @{} }
    if (-not $script:EnsuredLogDirs.ContainsKey($parent)) {
        if (-not (Test-Path $parent)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
        $script:EnsuredLogDirs[$parent] = $true
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogPath -Value "[$timestamp] $Message" -Encoding UTF8
}

function Write-ActionMessage {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Ctx,
        [Parameter(Mandatory)][string]$ActionName,
        [Parameter(Mandatory)][string]$Message
    )

    $logPath = Get-ActionLogPath -Ctx $Ctx -ActionName $ActionName
    Write-ActionLog -LogPath $logPath -Message $Message
}