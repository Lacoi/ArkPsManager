Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Native memory query - avoids the WMI/CIM overhead of Get-CimInstance Win32_OperatingSystem
if (-not ("Native.MemoryStatus" -as [type])) {
    Add-Type -Namespace Native -Name MemoryStatus -MemberDefinition @'
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
'@
}

# ---------------------------
# Config handling
# ---------------------------
$configPath = Join-Path $PSScriptRoot "config.json"

function Get-DefaultConfig {
    [PSCustomObject]@{
        GlobalSettings = [PSCustomObject]@{
            Process = [PSCustomObject]@{
                Name = "ArkAscendedServer"
                Path = "ShooterGame\Binaries\Win64"
                RestartEnabled = $false
                RestartTime = 300
            }
            Ini = [PSCustomObject]@{
                Path = "ShooterGame\Saved\Config\WindowsServer"
                File = "GameUserSettings.ini"
            }
            Startup = [PSCustomObject]@{
                Path  = "ShooterGame\Saved\Config\WindowsServer"
                File  = "RunServer.cmd"
                Delay = 5
            }
            Backup = [PSCustomObject]@{
                Path = "E:\Backup\ArkAsaNew"
                DailyToKeep = 7
                WeeklyToKeep = 4
            }
        }
        Entries = @()
    }
}

function Read-Config {
    if (Test-Path $configPath) {
        try {
            $json = Get-Content $configPath -Raw | ConvertFrom-Json
            $defaults = Get-DefaultConfig
            if (-not $json.GlobalSettings) {
                $json | Add-Member -NotePropertyName GlobalSettings -NotePropertyValue $defaults.GlobalSettings
            }
            if (-not $json.GlobalSettings.Process) {
                $json.GlobalSettings | Add-Member -NotePropertyName Process -NotePropertyValue $defaults.GlobalSettings.Process
            }
            if (-not $json.GlobalSettings.Ini) {
                $json.GlobalSettings | Add-Member -NotePropertyName Ini -NotePropertyValue $defaults.GlobalSettings.Ini
            }
            if (-not $json.GlobalSettings.Startup) {
                $json.GlobalSettings | Add-Member -NotePropertyName Startup -NotePropertyValue $defaults.GlobalSettings.Startup
            }
            if (-not $json.GlobalSettings.Backup) {
                $json.GlobalSettings | Add-Member -NotePropertyName Backup -NotePropertyValue $defaults.GlobalSettings.Backup
            }
            $entries = [System.Collections.ArrayList]::new()
            if ($json.Entries) {
                foreach ($e in $json.Entries) {
                    [void]$entries.Add([PSCustomObject]@{
                        Key              = $e.Key
                        ServerPath       = $e.ServerPath
                        ConfigPath       = Join-Path $PSScriptRoot (Join-Path "config/maps" $e.Key)
                        UseLatestBuild   = [bool]$e.UseLatestBuild
                        Pid              = $null   # runtime only, not persisted
                        RamGB            = $null   # runtime only, not persisted
                        CpuPercent       = $null   # runtime only, not persisted
                        StartTime        = $null   # runtime only, not persisted
                        SessionName      = $null   # runtime only, cached at startup / manual refresh
                        StoppedSince     = $null   # runtime only, used by the auto-restart check
                        RestartTriggered = $false  # runtime only, used by the auto-restart check
                        RestartEnabled   = $false  # runtime only, used by the auto-restart check
                    })
                }
            }
            return [PSCustomObject]@{
                GlobalSettings = $json.GlobalSettings
                Entries        = $entries
            }
        } catch {
            Write-Warning "Failed to read config, starting fresh: $_"
        }
    }
    $default = Get-DefaultConfig
    $default.Entries = [System.Collections.ArrayList]::new()
    return $default
}

function Save-Config {
    # Only persist Entries (Key/ServerPath). GlobalSettings is intentionally NOT
    # written here - it is only ever saved via the Settings dialog (Settings.ps1),
    # so App.ps1 never overwrites GlobalSettings in config.json.
    $entriesToSave = $script:config.Entries | ForEach-Object {
        [PSCustomObject]@{
            Key            = $_.Key
            ServerPath     = $_.ServerPath
            UseLatestBuild = $_.UseLatestBuild
        }
    }

    # Read the current GlobalSettings straight from disk so we don't clobber it
    # with whatever happens to be in memory (which may be stale).
    $currentGlobalSettings = $script:config.GlobalSettings
    if (Test-Path $configPath) {
        try {
            $onDisk = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($onDisk.GlobalSettings) {
                $currentGlobalSettings = $onDisk.GlobalSettings
            }
        } catch {
            Write-Warning "Failed to read existing config.json before saving entries: $_"
        }
    }

    $obj = [PSCustomObject]@{
        GlobalSettings = $currentGlobalSettings
        Entries        = @($entriesToSave)
    }
    $obj | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
}

$script:config = Read-Config

# ---------------------------
# Persist a single GlobalSettings.Process value without touching the rest of GlobalSettings
# ---------------------------
function Set-RestartEnabled {
    param([bool]$Enabled)

    $script:config.GlobalSettings.Process.RestartEnabled = $Enabled

    if (-not (Test-Path $configPath)) { return }
    try {
        $onDisk = Get-Content $configPath -Raw | ConvertFrom-Json
        # Ensure structure exists
        if (-not $onDisk.GlobalSettings) { $onDisk | Add-Member -NotePropertyName GlobalSettings -NotePropertyValue @{} }
        if (-not $onDisk.GlobalSettings.Process) { $onDisk.GlobalSettings | Add-Member -NotePropertyName Process -NotePropertyValue @{} }
        # Update only the target property
        $onDisk.GlobalSettings.Process.RestartEnabled = $Enabled
        $onDisk | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
    } catch {
        Write-Warning "Failed to persist RestartEnabled setting: $_"
    }
}

# ---------------------------
# Settings dialog (Settings.ps1) - loaded defensively
# ---------------------------
$settingsScriptPath = Join-Path $PSScriptRoot "Settings.ps1"
$script:settingsAvailable = $false

if (Test-Path $settingsScriptPath) {
    try {
        . $settingsScriptPath

        if (Get-Command -Name Show-SettingsDialog -ErrorAction SilentlyContinue) {
            $script:settingsAvailable = $true
        } else {
            Write-Warning "Settings.ps1 was loaded but does not define 'Show-SettingsDialog'."
        }
    } catch {
        Write-Warning "Failed to load Settings.ps1: $_"
    }
} else {
    Write-Warning "Settings.ps1 not found at: $settingsScriptPath"
}

# ---------------------------
# INI helper (single-key wrapper for Common.ps1's multi-key version)
# ---------------------------
function Get-IniValue {
    param(
        [string]$FilePath,
        [string]$Section,
        [string]$Key
    )

    if (-not (Test-Path $FilePath)) { return $null }

    try {
        $lines = Get-Content -Path $FilePath -ErrorAction Stop
    } catch {
        Write-Warning "Failed to read ini file '$FilePath': $_"
        return $null
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
            if ($k -eq $Key) {
                return $v
            }
        }
    }
    return $null
}

# ---------------------------
# Process matching
# ---------------------------
function Update-ProcessMatches {
    $procName = $script:config.GlobalSettings.Process.Name
    $procSubPath = $script:config.GlobalSettings.Process.Path

    foreach ($entry in $script:config.Entries) {
        $entry.Pid = $null
        $entry.RamGB = $null
        $entry.StartTime = $null
        $entry.CpuPercent = $null
    }

    if ([string]::IsNullOrWhiteSpace($procName)) {
        return
    }

    # Get-Process is used instead of Get-CimInstance/WMI since all target processes
    # run under the same user account, avoiding COM/MI marshalling overhead entirely.
    $baseName = $procName -replace '\.exe$', ''
    $procs = Get-Process -Name $baseName -ErrorAction SilentlyContinue

    if (-not $procs) { return }

    $procsByDir = @{}
    foreach ($proc in $procs) {
        $exePath = $null
        try { $exePath = $proc.Path } catch { continue }
        if (-not $exePath) { continue }
        $procDir = (Split-Path $exePath -Parent).TrimEnd('\').ToLowerInvariant()
        if (-not $procsByDir.ContainsKey($procDir)) {
            $procsByDir[$procDir] = $proc
        }
    }

    # CPU% needs two TotalProcessorTime samples over a wall-clock interval; only matched PIDs are kept each pass
    if (-not $script:cpuSamples) { $script:cpuSamples = @{} }
    $newCpuSamples = @{}
    $now = Get-Date

    foreach ($entry in $script:config.Entries) {
        if ([string]::IsNullOrWhiteSpace($entry.ServerPath)) { continue }

        $expectedPath = (Join-Path $entry.ServerPath $procSubPath).TrimEnd('\').ToLowerInvariant()

        if ($procsByDir.ContainsKey($expectedPath)) {
            $matchedProc = $procsByDir[$expectedPath]
            $entry.Pid = $matchedProc.Id
            $entry.RamGB = [math]::Round($matchedProc.WorkingSet64 / 1GB, 2)
            try { $entry.StartTime = $matchedProc.StartTime } catch { }

            try {
                $cpuTime = $matchedProc.TotalProcessorTime
                $prevSample = $script:cpuSamples[$matchedProc.Id]
                # Only trust the previous sample if it's the same process instance (StartTime matches)
                if ($prevSample -and $entry.StartTime -and $prevSample.ProcStartTime -eq $entry.StartTime) {
                    $elapsedMs = ($now - $prevSample.SampleTime).TotalMilliseconds
                    if ($elapsedMs -gt 0) {
                        $cpuDeltaMs = ($cpuTime - $prevSample.CpuTime).TotalMilliseconds
                        $cpuPercent = ($cpuDeltaMs / $elapsedMs / [Environment]::ProcessorCount) * 100
                        $entry.CpuPercent = [math]::Round([math]::Max(0, $cpuPercent), 1)
                    }
                }
                $newCpuSamples[$matchedProc.Id] = [PSCustomObject]@{
                    CpuTime      = $cpuTime
                    SampleTime   = $now
                    ProcStartTime = $entry.StartTime
                }
            } catch { }
        }
    }

    # Drop samples for PIDs no longer matched, so the cache doesn't grow unbounded
    $script:cpuSamples = $newCpuSamples

    # Process objects hold native handles - dispose now that values have been copied out
    foreach ($proc in $procs) { 
        try { $proc.Dispose() } catch { } 
    }
}

# ---------------------------
# Ini-based SessionName lookup (only called at startup and on manual "Refresh Processes")
# ---------------------------
function Update-SessionNames {
    $iniPath = $script:config.GlobalSettings.Ini.Path
    $iniFile = $script:config.GlobalSettings.Ini.File

    foreach ($entry in $script:config.Entries) {
        $entry.SessionName = $null

        if ([string]::IsNullOrWhiteSpace($entry.ServerPath) -or [string]::IsNullOrWhiteSpace($iniPath) -or [string]::IsNullOrWhiteSpace($iniFile)) {
            continue
        }

        $fullIniPath = Join-Path (Join-Path $entry.ServerPath $iniPath) $iniFile
        $entry.SessionName = Get-IniValue -FilePath $fullIniPath -Section "SessionSettings" -Key "SessionName"
    }
}

# ---------------------------
# Action scripts folder
# ---------------------------
$script:actionsFolder = Join-Path $PSScriptRoot "actions"
if (-not (Test-Path $script:actionsFolder)) {
    New-Item -Path $script:actionsFolder -ItemType Directory -Force | Out-Null
}

# ---------------------------
# Action script validation helper
# ---------------------------
function Test-ActionScript {
    param(
        [string]$ScriptPath
    )

    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        return [PSCustomObject]@{ IsValid = $false; Reason = "No script path was provided." }
    }

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return [PSCustomObject]@{ IsValid = $false; Reason = "Script not found:`n$ScriptPath" }
    }

    # Basic syntax check so a broken script fails fast with a clear message
    # instead of opening a PowerShell window that immediately errors out.
    try {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            $errText = ($parseErrors | ForEach-Object { $_.Message }) -join "`n"
            return [PSCustomObject]@{ IsValid = $false; Reason = "Script has syntax errors:`n$ScriptPath`n`n$errText" }
        }
    } catch {
        return [PSCustomObject]@{ IsValid = $false; Reason = "Failed to validate script:`n$ScriptPath`n`n$_" }
    }

    return [PSCustomObject]@{ IsValid = $true; Reason = $null }
}

# ---------------------------
# ServerPath validation helper - rejects UNC paths and drive letters mapped to network shares
# ---------------------------
function Test-LocalDrivePath {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }

    if ($Path -match '^\\\\') { return $false }

    $driveLetter = ($Path -split ':', 2)[0]
    if ([string]::IsNullOrWhiteSpace($driveLetter) -or $driveLetter.Length -ne 1) { return $false }

    try {
        $driveInfo = [System.IO.DriveInfo]::new("$driveLetter`:")
        return $driveInfo.DriveType -eq [System.IO.DriveType]::Fixed
    } catch {
        return $false
    }
}

# ---------------------------
# Global action functions (one per button, triggered with the entry's Key)
# ---------------------------
function Invoke-EntryAction {
    param(
        [string]$ScriptName,
        [string]$Key
    )

    $scriptPath = Join-Path $script:actionsFolder "$ScriptName.ps1"

    $check = Test-ActionScript -ScriptPath $scriptPath
    if (-not $check.IsValid) {
        [System.Windows.Forms.MessageBox]::Show(
            $check.Reason,
            "Action Script Unavailable",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $argList = @(
        #"-NoExit" # Uncomment for debugging the action script in a new PowerShell window
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$scriptPath`""
        "-Key", "`"$Key`""
        "-ConfigJsonPath", "`"$configPath`""
    )

    try {
        Start-Process -FilePath "pwsh.exe" -ArgumentList $argList -WindowStyle Normal
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error launching '$ScriptName.ps1' for '$Key':`n$_", "Script Error") | Out-Null
    }
}

function Invoke-EntryStart   { param([string]$Key) Invoke-EntryAction -ScriptName "Start"   -Key $Key }
function Invoke-EntryRestart { param([string]$Key) Invoke-EntryAction -ScriptName "Restart" -Key $Key }
function Invoke-EntryStop    { param([string]$Key) Invoke-EntryAction -ScriptName "Stop"    -Key $Key }
function Invoke-EntryKill    {
    param([string]$Key)
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Are you sure you want to kill '$Key'?",
        "Confirm Kill",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    Invoke-EntryAction -ScriptName "Kill" -Key $Key
}
function Invoke-EntryBackup  { param([string]$Key) Invoke-EntryAction -ScriptName "Backup"  -Key $Key }
function Invoke-EntryUpdate  { param([string]$Key) Invoke-EntryAction -ScriptName "Update"  -Key $Key }

# ---------------------------
# Bulk action functions (apply the same action to ALL currently selected rows)
# ---------------------------
function Invoke-BulkAction {
    param([string]$ScriptName)

    if ($grid.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one entry first.", "Info") | Out-Null
        return
    }

    $keys = @($grid.SelectedRows | ForEach-Object { $_.Cells["KeyCol"].Value })
    foreach ($k in $keys) {
        Invoke-EntryAction -ScriptName $ScriptName -Key $k
    }
}

function Invoke-BulkStart   { Invoke-BulkAction -ScriptName "Start" }
function Invoke-BulkRestart { Invoke-BulkAction -ScriptName "Restart" }
function Invoke-BulkStop    { Invoke-BulkAction -ScriptName "Stop" }
function Invoke-BulkKill    {
    if ($grid.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one entry first.", "Info") | Out-Null
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Are you sure you want to kill the $($grid.SelectedRows.Count) selected entries?",
        "Confirm Kill",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $keys = @($grid.SelectedRows | ForEach-Object { $_.Cells["KeyCol"].Value })
    foreach ($k in $keys) {
        Invoke-EntryAction -ScriptName "Kill" -Key $k
    }
}
function Invoke-BulkBackup  { Invoke-BulkAction -ScriptName "Backup" }
function Invoke-BulkUpdate  { Invoke-BulkAction -ScriptName "Update" }

# ---------------------------
# UpdateCache action (standalone, no arguments passed at all)
# ---------------------------
function Invoke-UpdateCache {
    $scriptPath = Join-Path $script:actionsFolder "UpdateCache.ps1"

    $check = Test-ActionScript -ScriptPath $scriptPath
    if (-not $check.IsValid) {
        [System.Windows.Forms.MessageBox]::Show(
            $check.Reason,
            "Action Script Unavailable",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $argList = @(
        #"-NoExit" # Uncomment for debugging the action script in a new PowerShell window
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$scriptPath`""
    )

    try {
        Start-Process -FilePath "pwsh.exe" -ArgumentList $argList -WindowStyle Normal
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error launching 'UpdateCache.ps1':`n$_", "Script Error") | Out-Null
    }
}

# ---------------------------
# CreateServerSettings action (standalone, no arguments passed at all)
# ---------------------------
function Invoke-CreateServerSettings {
    $scriptPath = Join-Path $script:actionsFolder "CreateServerSettings.ps1"

    $check = Test-ActionScript -ScriptPath $scriptPath
    if (-not $check.IsValid) {
        [System.Windows.Forms.MessageBox]::Show(
            $check.Reason,
            "Action Script Unavailable",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $argList = @(
        #"-NoExit" # Uncomment for debugging the action script in a new PowerShell window
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$scriptPath`""
    )

    try {
        Start-Process -FilePath "pwsh.exe" -ArgumentList $argList -WindowStyle Normal
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error launching 'CreateServerSettings.ps1':`n$_", "Script Error") | Out-Null
    }
}

# ---------------------------
# PinPreviousBuild action (standalone, pins Cache\Server_<buildid> for the 2nd-most-recent build)
# ---------------------------
function Invoke-PinPreviousBuild {
    $cacheDir = Join-Path $PSScriptRoot "Cache"

    $versionedDirs = Get-ChildItem -Path $cacheDir -Directory -Filter "Server_*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Server_(\d+)$' } |
        ForEach-Object { [PSCustomObject]@{ Path = $_.FullName; BuildId = [int64]$Matches[1] } } |
        Sort-Object BuildId -Descending

    if ($versionedDirs.Count -lt 2) {
        [System.Windows.Forms.MessageBox]::Show("Need at least 2 versioned cache snapshots (Cache\Server_<buildid>) to pin the previous build. Run 'UpdateCache' a few times first.", "Info") | Out-Null
        return
    }

    $previousBuild = $versionedDirs[1]

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Pin build $($previousBuild.BuildId) as the cache used by 'Update' for entries without 'Use Latest Build' checked?`n`nAny existing pin will be replaced.",
        "Confirm Pin Previous Build",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        Get-ChildItem -Path $cacheDir -Filter "*.build" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        New-Item -Path (Join-Path $cacheDir "$($previousBuild.BuildId).build") -ItemType File -Force | Out-Null
        [System.Windows.Forms.MessageBox]::Show("Pinned build $($previousBuild.BuildId).", "Pinned") | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to pin build $($previousBuild.BuildId):`n$_", "Error") | Out-Null
    }
}

# ---------------------------
# Form
# ---------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Server Config Manager"
$form.Size = New-Object System.Drawing.Size(900, 760)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# ---- Top bar: Settings + Reload Global Settings buttons ----
$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.Text = "Settings"
$btnSettings.Location = New-Object System.Drawing.Point(15, 15)
$btnSettings.Size = New-Object System.Drawing.Size(150, 32)
$form.Controls.Add($btnSettings)

if (-not $script:settingsAvailable) {
    $btnSettings.Enabled = $false
    $btnSettings.Text = "Settings (unavailable)"
}

$btnSettings.Add_Click({
    if (-not $script:settingsAvailable) {
        [System.Windows.Forms.MessageBox]::Show(
            "Settings.ps1 could not be found or loaded.`nExpected at:`n$settingsScriptPath`n`nGlobal settings cannot be edited until this file is available.",
            "Settings Unavailable",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    try {
        Show-SettingsDialog -ConfigJsonPath $configPath
    } catch {
        [System.Windows.Forms.MessageBox]::Show("An error occurred while opening the Settings dialog:`n$_", "Settings Error") | Out-Null
        return
    }

    # Reload GlobalSettings from disk after the dialog closes, keep in-memory Entries as-is
    try {
        $reloaded = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($reloaded.GlobalSettings) {
            $script:config.GlobalSettings = $reloaded.GlobalSettings
        }
    } catch {
        Write-Warning "Failed to reload GlobalSettings after closing Settings dialog: $_"
    }
})

$btnReloadSettings = New-Object System.Windows.Forms.Button
$btnReloadSettings.Text = "Reload Global Settings"
$btnReloadSettings.Location = New-Object System.Drawing.Point(175, 15)
$btnReloadSettings.Size = New-Object System.Drawing.Size(170, 32)
$form.Controls.Add($btnReloadSettings)

$btnReloadSettings.Add_Click({
    if (-not (Test-Path $configPath)) {
        [System.Windows.Forms.MessageBox]::Show("Config file not found:`n$configPath", "Error") | Out-Null
        return
    }

    try {
        $reloaded = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($reloaded.GlobalSettings) {
            $script:config.GlobalSettings = $reloaded.GlobalSettings
            [System.Windows.Forms.MessageBox]::Show("Global settings reloaded from config.json.", "Reloaded") | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("No GlobalSettings found in config.json.", "Info") | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to reload global settings:`n$_", "Error") | Out-Null
    }
})

# ---- Entry input GroupBox ----
$grpEntry = New-Object System.Windows.Forms.GroupBox
$grpEntry.Text = "Add / Edit Entry"
$grpEntry.Location = New-Object System.Drawing.Point(15, 60)
$grpEntry.Size = New-Object System.Drawing.Size(855, 100)
$form.Controls.Add($grpEntry)

$lblKey = New-Object System.Windows.Forms.Label
$lblKey.Text = "Key:"
$lblKey.Location = New-Object System.Drawing.Point(15, 25)
$lblKey.Size = New-Object System.Drawing.Size(40, 20)
$grpEntry.Controls.Add($lblKey)

$txtKey = New-Object System.Windows.Forms.TextBox
$txtKey.Location = New-Object System.Drawing.Point(60, 22)
$txtKey.Size = New-Object System.Drawing.Size(200, 24)
$grpEntry.Controls.Add($txtKey)

$lblServerPath = New-Object System.Windows.Forms.Label
$lblServerPath.Text = "ServerPath:"
$lblServerPath.Location = New-Object System.Drawing.Point(270, 25)
$lblServerPath.Size = New-Object System.Drawing.Size(90, 20)
$grpEntry.Controls.Add($lblServerPath)

$txtServerPath = New-Object System.Windows.Forms.TextBox
$txtServerPath.Location = New-Object System.Drawing.Point(365, 22)
$txtServerPath.Size = New-Object System.Drawing.Size(465, 24)
$grpEntry.Controls.Add($txtServerPath)

$lblConfigPath = New-Object System.Windows.Forms.Label
$lblConfigPath.Text = "ConfigPath:"
$lblConfigPath.Location = New-Object System.Drawing.Point(15, 55)
$lblConfigPath.Size = New-Object System.Drawing.Size(90, 20)
$grpEntry.Controls.Add($lblConfigPath)

$txtConfigPath = New-Object System.Windows.Forms.TextBox
$txtConfigPath.Location = New-Object System.Drawing.Point(110, 52)
$txtConfigPath.Size = New-Object System.Drawing.Size(550, 24)
$txtConfigPath.ReadOnly = $true
$grpEntry.Controls.Add($txtConfigPath)

$chkUseLatestBuild = New-Object System.Windows.Forms.CheckBox
$chkUseLatestBuild.Text = "Use Latest Build"
$chkUseLatestBuild.Location = New-Object System.Drawing.Point(670, 55)
$chkUseLatestBuild.Size = New-Object System.Drawing.Size(160, 20)
$grpEntry.Controls.Add($chkUseLatestBuild)

# ---- Buttons for entry actions ----
$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = "Add Entry"
$btnAdd.Location = New-Object System.Drawing.Point(15, 170)
$btnAdd.Size = New-Object System.Drawing.Size(110, 28)
$form.Controls.Add($btnAdd)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = "Update Selected"
$btnUpdate.Location = New-Object System.Drawing.Point(135, 170)
$btnUpdate.Size = New-Object System.Drawing.Size(130, 28)
$form.Controls.Add($btnUpdate)

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = "Remove Selected"
$btnRemove.Location = New-Object System.Drawing.Point(275, 170)
$btnRemove.Size = New-Object System.Drawing.Size(130, 28)
$form.Controls.Add($btnRemove)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "Clear Fields"
$btnClear.Location = New-Object System.Drawing.Point(415, 170)
$btnClear.Size = New-Object System.Drawing.Size(100, 28)
$form.Controls.Add($btnClear)

$btnRefreshProc = New-Object System.Windows.Forms.Button
$btnRefreshProc.Text = "Refresh Processes"
$btnRefreshProc.Location = New-Object System.Drawing.Point(745, 170)
$btnRefreshProc.Size = New-Object System.Drawing.Size(125, 28)
$form.Controls.Add($btnRefreshProc)

# ---- System RAM usage bar (above the grid) ----
$progressRam = New-Object System.Windows.Forms.ProgressBar
$progressRam.Location = New-Object System.Drawing.Point(15, 208)
$progressRam.Size = New-Object System.Drawing.Size(855, 16)
$progressRam.Minimum = 0
$progressRam.Maximum = 100
$form.Controls.Add($progressRam)

# ---- DataGridView for entries (supports per-row action buttons + multi-select) ----
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(15, 232)
$grid.Size = New-Object System.Drawing.Size(855, 358)
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = "FullRowSelect"
$grid.MultiSelect = $true
$grid.AutoSizeColumnsMode = "None"
$grid.AllowUserToResizeRows = $false
$form.Controls.Add($grid)

$colKey = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colKey.Name = "KeyCol"
$colKey.HeaderText = "Key"
$colKey.SortMode = "NotSortable"
$colKey.Visible = $false
[void]$grid.Columns.Add($colKey)

$colPid = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPid.Name = "Pid"
$colPid.HeaderText = "PID"
$colPid.SortMode = "NotSortable"
$colPid.Width = 60
$colPid.ReadOnly = $true
[void]$grid.Columns.Add($colPid)

$colSession = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSession.Name = "SessionName"
$colSession.HeaderText = "Session Name"
$colSession.SortMode = "NotSortable"
$colSession.Width = 215
$colSession.ReadOnly = $true
[void]$grid.Columns.Add($colSession)

$colRam = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colRam.Name = "RamGB"
$colRam.HeaderText = "RAM (GB)"
$colRam.SortMode = "NotSortable"
$colRam.Width = 80
$colRam.ReadOnly = $true
[void]$grid.Columns.Add($colRam)

$colCpu = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colCpu.Name = "CpuPercent"
$colCpu.HeaderText = "CPU %"
$colCpu.SortMode = "NotSortable"
$colCpu.Width = 70
$colCpu.ReadOnly = $true
[void]$grid.Columns.Add($colCpu)

$colStart = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colStart.Name = "StartTime"
$colStart.HeaderText = "Start Time"
$colStart.SortMode = "NotSortable"
$colStart.Width = 130
$colStart.ReadOnly = $true
[void]$grid.Columns.Add($colStart)

function New-ActionButtonColumn($name, $text, $width) {
    $col = New-Object System.Windows.Forms.DataGridViewButtonColumn
    $col.Name = $name
    $col.HeaderText = ""
    $col.Text = $text
    $col.UseColumnTextForButtonValue = $true
    $col.Width = $width
    return $col
}

[void]$grid.Columns.Add((New-ActionButtonColumn "BtnStart"   "Start"   60))
[void]$grid.Columns.Add((New-ActionButtonColumn "BtnRestart" "Restart" 65))
[void]$grid.Columns.Add((New-ActionButtonColumn "BtnStop"    "Stop"    55))
[void]$grid.Columns.Add((New-ActionButtonColumn "BtnKill"    "Kill"    55))
[void]$grid.Columns.Add((New-ActionButtonColumn "BtnBackup"  "Backup"  65))
[void]$grid.Columns.Add((New-ActionButtonColumn "BtnUpdate"  "Update"  65))

# ---- Bulk action buttons (apply the same action to all selected rows) ----
$grpBulk = New-Object System.Windows.Forms.GroupBox
$grpBulk.Text = "Bulk Actions (selected entries)"
$grpBulk.Location = New-Object System.Drawing.Point(15, 600)
$grpBulk.Size = New-Object System.Drawing.Size(500, 60)
$form.Controls.Add($grpBulk)

$btnBulkStart = New-Object System.Windows.Forms.Button
$btnBulkStart.Text = "Start"
$btnBulkStart.Location = New-Object System.Drawing.Point(10, 22)
$btnBulkStart.Size = New-Object System.Drawing.Size(75, 28)
$grpBulk.Controls.Add($btnBulkStart)

$btnBulkRestart = New-Object System.Windows.Forms.Button
$btnBulkRestart.Text = "Restart"
$btnBulkRestart.Location = New-Object System.Drawing.Point(90, 22)
$btnBulkRestart.Size = New-Object System.Drawing.Size(75, 28)
$grpBulk.Controls.Add($btnBulkRestart)

$btnBulkStop = New-Object System.Windows.Forms.Button
$btnBulkStop.Text = "Stop"
$btnBulkStop.Location = New-Object System.Drawing.Point(170, 22)
$btnBulkStop.Size = New-Object System.Drawing.Size(75, 28)
$grpBulk.Controls.Add($btnBulkStop)

$btnBulkKill = New-Object System.Windows.Forms.Button
$btnBulkKill.Text = "Kill"
$btnBulkKill.Location = New-Object System.Drawing.Point(250, 22)
$btnBulkKill.Size = New-Object System.Drawing.Size(75, 28)
$grpBulk.Controls.Add($btnBulkKill)

$btnBulkBackup = New-Object System.Windows.Forms.Button
$btnBulkBackup.Text = "Backup"
$btnBulkBackup.Location = New-Object System.Drawing.Point(330, 22)
$btnBulkBackup.Size = New-Object System.Drawing.Size(75, 28)
$grpBulk.Controls.Add($btnBulkBackup)

$btnBulkUpdate = New-Object System.Windows.Forms.Button
$btnBulkUpdate.Text = "Update"
$btnBulkUpdate.Location = New-Object System.Drawing.Point(410, 22)
$btnBulkUpdate.Size = New-Object System.Drawing.Size(75, 28)
$grpBulk.Controls.Add($btnBulkUpdate)

$btnBulkStart.Add_Click({ Invoke-BulkStart })
$btnBulkRestart.Add_Click({ Invoke-BulkRestart })
$btnBulkStop.Add_Click({ Invoke-BulkStop })
$btnBulkKill.Add_Click({ Invoke-BulkKill })
$btnBulkBackup.Add_Click({ Invoke-BulkBackup })
$btnBulkUpdate.Add_Click({ Invoke-BulkUpdate })

# ---- UpdateCache button (standalone action, no entry context) ----
$btnUpdateCache = New-Object System.Windows.Forms.Button
$btnUpdateCache.Text = "UpdateCache"
$btnUpdateCache.Location = New-Object System.Drawing.Point(15, 680)
$btnUpdateCache.Size = New-Object System.Drawing.Size(120, 28)
$form.Controls.Add($btnUpdateCache)

$btnUpdateCache.Add_Click({ Invoke-UpdateCache })

# ---- Pin Previous Build button (standalone action, no entry context) ----
$btnPinPreviousBuild = New-Object System.Windows.Forms.Button
$btnPinPreviousBuild.Text = "Pin Previous Build"
$btnPinPreviousBuild.Location = New-Object System.Drawing.Point(145, 680)
$btnPinPreviousBuild.Size = New-Object System.Drawing.Size(150, 28)
$form.Controls.Add($btnPinPreviousBuild)

$btnPinPreviousBuild.Add_Click({ Invoke-PinPreviousBuild })

# ---- Auto-restart toggle (reflects/persists GlobalSettings.Process.RestartEnabled) ----
$chkRestartEnabled = New-Object System.Windows.Forms.CheckBox
$chkRestartEnabled.Text = "Auto-restart stopped servers"
$chkRestartEnabled.Location = New-Object System.Drawing.Point(305, 685)
$chkRestartEnabled.Size = New-Object System.Drawing.Size(200, 20)
$chkRestartEnabled.Checked = [bool]$script:config.GlobalSettings.Process.RestartEnabled
$form.Controls.Add($chkRestartEnabled)

# ---- CreateServerSettings button (standalone action, no entry context) ----
$btnCreateServerSettings = New-Object System.Windows.Forms.Button
$btnCreateServerSettings.Text = "Create Server Settings"
$btnCreateServerSettings.Location = New-Object System.Drawing.Point(680, 680)
$btnCreateServerSettings.Size = New-Object System.Drawing.Size(190, 28)
$form.Controls.Add($btnCreateServerSettings)

$btnCreateServerSettings.Add_Click({ Invoke-CreateServerSettings })

# ---- Status label showing last refresh time ----
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.Location = New-Object System.Drawing.Point(525, 610)
$lblStatus.Size = New-Object System.Drawing.Size(345, 20)
$lblStatus.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblStatus)

# ---- Managed servers RAM usage label ----
$lblRamUsage = New-Object System.Windows.Forms.Label
$lblRamUsage.Text = "Total RAM usage: -"
$lblRamUsage.Location = New-Object System.Drawing.Point(525, 630)
$lblRamUsage.Size = New-Object System.Drawing.Size(345, 20)
$lblRamUsage.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblRamUsage)

# ---------------------------
# Populate grid from config
# ---------------------------
function Reset-GridRows {
    # Full rebuild - only needed when entries are added/removed/renamed or at startup
    $selectedKeys = @($grid.SelectedRows | ForEach-Object { $_.Cells["KeyCol"].Value })

    $grid.Rows.Clear()
    foreach ($e in $script:config.Entries) {
        $rowIndex = $grid.Rows.Add()
        $grid.Rows[$rowIndex].Cells["KeyCol"].Value = $e.Key
    }

    if ($selectedKeys.Count -gt 0) {
        foreach ($row in $grid.Rows) {
            if ($selectedKeys -contains $row.Cells["KeyCol"].Value) {
                $row.Selected = $true
            }
        }
    }

    Update-Grid
}

function Update-Grid {
    # Lightweight refresh - updates runtime fields on existing rows in place, no row rebuild
    # Build hashtable for O(1) lookups instead of O(n) Where-Object searches
    $entriesByKey = @{}
    foreach ($e in $script:config.Entries) { 
        $entriesByKey[$e.Key] = $e 
    }
    
    foreach ($row in $grid.Rows) {
        $key = $row.Cells["KeyCol"].Value
        $entry = $entriesByKey[$key]
        if (-not $entry) { continue }

        $pidRestartText = if ($entry.RestartEnabled -eq $false) { " NR" } else { " R" }
        $pidText = if ($entry.Pid) { [string]$entry.Pid + $pidRestartText } else { "-" + $pidRestartText }
        $sessionText = if ($entry.SessionName) { $entry.SessionName } else { "-" }
        $ramText = if ($null -ne $entry.RamGB) { "{0:N2}" -f $entry.RamGB } else { "-" }
        $cpuText = if ($null -ne $entry.CpuPercent) { "{0:N1}" -f $entry.CpuPercent } else { "-" }
        $startText = if ($entry.StartTime) { $entry.StartTime.ToString("dd.MM.yyyy HH:mm:ss") } else { if ($entry.StoppedSince) { "off: " + $entry.StoppedSince.ToString("dd.MM.yyyy HH:mm:ss") } else { "-" } }

        if ($row.Cells["Pid"].Value -ne $pidText) { $row.Cells["Pid"].Value = $pidText }
        if ($row.Cells["SessionName"].Value -ne $sessionText) { $row.Cells["SessionName"].Value = $sessionText }
        if ($row.Cells["RamGB"].Value -ne $ramText) { $row.Cells["RamGB"].Value = $ramText }
        if ($row.Cells["CpuPercent"].Value -ne $cpuText) { $row.Cells["CpuPercent"].Value = $cpuText }
        if ($row.Cells["StartTime"].Value -ne $startText) { $row.Cells["StartTime"].Value = $startText }
    }

    if ($grid.SelectedRows.Count -eq 1) {
        $selectedKey = $grid.SelectedRows[0].Cells["KeyCol"].Value
        $entry = $entriesByKey[$selectedKey]
        if ($entry) {
            $txtKey.Text        = $entry.Key
            $txtServerPath.Text = $entry.ServerPath
            $txtConfigPath.Text = $entry.ConfigPath
            $chkUseLatestBuild.Checked = [bool]$entry.UseLatestBuild
        }
    } else {
        $txtKey.Clear()
        $txtServerPath.Clear()
        $txtConfigPath.Clear()
        $chkUseLatestBuild.Checked = $false
    }

    $runningEntries = @($script:config.Entries | Where-Object { $null -ne $_.RamGB })
    $totalRamGB = ($runningEntries | Measure-Object -Property RamGB -Sum).Sum
    if ($runningEntries.Count -gt 0) {
        $lblRamUsage.Text = "Total RAM usage: {0:N2} GB ({1} server(s) running)" -f $totalRamGB, $runningEntries.Count
    } else {
        $lblRamUsage.Text = "Total RAM usage: - (no servers running)"
    }

    # Auto-restart any entry that has been stopped longer than GlobalSettings.Process.RestartTime
    $restartEnabled = [bool]$script:config.GlobalSettings.Process.RestartEnabled
    $restartTimeSeconds = [int]($script:config.GlobalSettings.Process.RestartTime)
    $startupPath = $script:config.GlobalSettings.Startup.Path
    $startupFile = $script:config.GlobalSettings.Startup.File
    foreach ($entry in $script:config.Entries) {
        if ([string]::IsNullOrWhiteSpace($entry.ServerPath)) { continue }

        if ($entry.Pid -or $null -eq $entry.SessionName -or -not $entry.RestartEnabled) {
            $entry.StoppedSince = $null
            $entry.RestartTriggered = $false
            continue
        }

        if (-not $restartEnabled -or $restartTimeSeconds -le 0) { continue }

        # Check if the expected startup script exists before attempting to auto-restart
        if (-not (Test-Path (Join-Path (Join-Path $entry.ServerPath $startupPath) "$startupFile") -PathType Leaf)) { continue }

        if (-not $entry.StoppedSince) {
            $entry.StoppedSince = Get-Date
        } elseif (-not $entry.RestartTriggered -and ((Get-Date) - $entry.StoppedSince).TotalSeconds -ge $restartTimeSeconds) {
            $entry.RestartTriggered = $true
            Invoke-EntryStart -Key $entry.Key
        }
    }

    try {
        $memStatus = New-Object Native.MemoryStatus+MEMORYSTATUSEX
        $memStatus.dwLength = [System.Runtime.InteropServices.Marshal]::SizeOf([type][Native.MemoryStatus+MEMORYSTATUSEX])
        if (-not [Native.MemoryStatus]::GlobalMemoryStatusEx([ref]$memStatus)) {
            throw "GlobalMemoryStatusEx failed"
        }
        $progressRam.Value = [math]::Max(0, [math]::Min(100, $memStatus.dwMemoryLoad))
    } catch {
        $progressRam.Value = 0
    }

    $lblStatus.Text = "Last refreshed: $(Get-Date -Format 'HH:mm:ss') (every 30s auto-refresh)"
}

function Update-AutorestartFlags {
    foreach ($entry in $script:config.Entries) {
        if ($null -ne $entry.Pid -and $null -ne $entry.SessionName) {
            $entry.RestartEnabled = $true
        }
    }
}

function Clear-EntryFields {
    $txtKey.Clear()
    $txtServerPath.Clear()
    $txtConfigPath.Clear()
    $chkUseLatestBuild.Checked = $false
    $grid.ClearSelection()
}

Update-ProcessMatches
Update-AutorestartFlags
Update-SessionNames
Reset-GridRows

# ---------------------------
# Auto-refresh timer (every 30 seconds) - process info only, SessionName is NOT re-read here
# ---------------------------
$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 30000
$refreshTimer.Add_Tick({
    Update-ProcessMatches
    Update-Grid
})
$refreshTimer.Start()

$form.Add_FormClosing({
    $refreshTimer.Stop()
    $refreshTimer.Dispose()
    Save-Config
})

# ---------------------------
# Event handlers
# ---------------------------
$txtKey.Add_TextChanged({
    $keyVal = $txtKey.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($keyVal)) {
        $txtConfigPath.Text = Join-Path $PSScriptRoot (Join-Path "config/maps" $keyVal)
    } else {
        $txtConfigPath.Clear()
    }
})

$btnAdd.Add_Click({
    $key = $txtKey.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($key)) {
        [System.Windows.Forms.MessageBox]::Show("Key is required.", "Info") | Out-Null
        return
    }
    if ($script:config.Entries | Where-Object { $_.Key -eq $key }) {
        [System.Windows.Forms.MessageBox]::Show("An entry with this Key already exists.", "Info") | Out-Null
        return
    }
    $serverPath = $txtServerPath.Text.Trim()
    if (-not (Test-LocalDrivePath -Path $serverPath)) {
        [System.Windows.Forms.MessageBox]::Show("ServerPath must be on a local (fixed) hard drive, not a UNC path or network drive.", "Info") | Out-Null
        return
    }
    [void]$script:config.Entries.Add([PSCustomObject]@{
        Key              = $key
        ServerPath       = $serverPath
        ConfigPath       = Join-Path $PSScriptRoot (Join-Path "config/maps" $key)
        UseLatestBuild   = $chkUseLatestBuild.Checked
        Pid              = $null
        RamGB            = $null
        CpuPercent       = $null
        StartTime        = $null
        SessionName      = $null
        StoppedSince     = $null
        RestartTriggered = $false
    })
    Update-ProcessMatches
    Reset-GridRows
    Clear-EntryFields
    Save-Config
})

$btnUpdate.Add_Click({
    if ($grid.SelectedRows.Count -ne 1) {
        [System.Windows.Forms.MessageBox]::Show("Select exactly one entry to update.", "Info") | Out-Null
        return
    }
    $selectedKey = $grid.SelectedRows[0].Cells["KeyCol"].Value
    $idx = -1
    for ($i = 0; $i -lt $script:config.Entries.Count; $i++) {
        if ($script:config.Entries[$i].Key -eq $selectedKey) { $idx = $i; break }
    }
    if ($idx -eq -1) { return }

    $key = $txtKey.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($key)) {
        [System.Windows.Forms.MessageBox]::Show("Key is required.", "Info") | Out-Null
        return
    }
    $serverPath = $txtServerPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($serverPath)) {
        [System.Windows.Forms.MessageBox]::Show("ServerPath is required.", "Info") | Out-Null
        return
    }
    if (-not (Test-LocalDrivePath -Path $serverPath)) {
        [System.Windows.Forms.MessageBox]::Show("ServerPath must be on a local (fixed) hard drive, not a UNC path or network drive.", "Info") | Out-Null
        return
    }
    $script:config.Entries[$idx].Key        = $key
    $script:config.Entries[$idx].ServerPath = $serverPath
    $script:config.Entries[$idx].ConfigPath = Join-Path $PSScriptRoot (Join-Path "config/maps" $key)
    $script:config.Entries[$idx].UseLatestBuild = $chkUseLatestBuild.Checked
    Update-ProcessMatches
    Reset-GridRows
    Clear-EntryFields
    Save-Config
})

$btnRemove.Add_Click({
    if ($grid.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one entry to remove.", "Info") | Out-Null
        return
    }

    $keysToRemove = @($grid.SelectedRows | ForEach-Object { $_.Cells["KeyCol"].Value })

    foreach ($k in $keysToRemove) {
        $idx = -1
        for ($i = 0; $i -lt $script:config.Entries.Count; $i++) {
            if ($script:config.Entries[$i].Key -eq $k) { $idx = $i; break }
        }
        if ($idx -ne -1) {
            $script:config.Entries.RemoveAt($idx)
        }
    }

    Reset-GridRows
    Clear-EntryFields
    Save-Config
})

$btnClear.Add_Click({ Clear-EntryFields })

$btnRefreshProc.Add_Click({
    Update-ProcessMatches
    Update-AutorestartFlags
    Update-SessionNames
    Update-Grid
})

$chkRestartEnabled.Add_CheckedChanged({
    Update-AutorestartFlags
    Set-RestartEnabled -Enabled $chkRestartEnabled.Checked
})

$grid.Add_SelectionChanged({
    if ($grid.SelectedRows.Count -eq 1) {
        $selectedKey = $grid.SelectedRows[0].Cells["KeyCol"].Value
        $entry = $script:config.Entries | Where-Object { $_.Key -eq $selectedKey } | Select-Object -First 1
        if ($entry) {
            $txtKey.Text        = $entry.Key
            $txtServerPath.Text = $entry.ServerPath
            $txtConfigPath.Text = $entry.ConfigPath
            $chkUseLatestBuild.Checked = [bool]$entry.UseLatestBuild
        }
    } else {
        $txtKey.Clear()
        $txtServerPath.Clear()
        $txtConfigPath.Clear()
        $chkUseLatestBuild.Checked = $false
    }
})

# ---- Handle per-row action button clicks ----
$grid.Add_CellContentClick({
    param($eventSender, $e)
    if ($e.RowIndex -lt 0) { return }

    $row = $grid.Rows[$e.RowIndex]
    $key = $row.Cells["KeyCol"].Value
    $columnName = $grid.Columns[$e.ColumnIndex].Name

    switch ($columnName) {
        "BtnStart"   { Invoke-EntryStart   -Key $key }
        "BtnRestart" { Invoke-EntryRestart -Key $key }
        "BtnStop"    { Invoke-EntryStop    -Key $key }
        "BtnKill"    { Invoke-EntryKill    -Key $key }
        "BtnBackup"  { Invoke-EntryBackup  -Key $key }
        "BtnUpdate"  { Invoke-EntryUpdate  -Key $key }
    }
})

# ---------------------------
# Show the form
# ---------------------------
[void]$form.ShowDialog()